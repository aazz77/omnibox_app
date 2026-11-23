//! 嵌入式直播内核：把原 axum handler 的高层逻辑收敛成纯 async 方法，
//! 由外层 omnibox_core 的 FFI 调用。无 HTTP / 无端口；播放地址返回原始 URL + 请求头，
//! 由 Flutter 端媒体内核（mpv/VLC）直连播放。
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use dashmap::DashMap;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::live_server::config::Config;
use crate::live_server::danmaku::{DanmakuHub, Subscription};
use crate::live_server::error::{AppError, ApiResult, IntoApi};
use crate::live_server::models::{DanmakuMessage, RoomDetail};
use crate::live_server::state::{AppState, RoomCache, Shared};
use crate::live_server::store::Settings;

/// 弹幕会话：有界消息队列，供 Dart 侧轮询拉取。
/// 上游 WS 订阅（Subscription）在独立 task 中持有并持续写入队列；
/// 会话移除（danmaku_stop）时 task 因订阅 Drop 而停止。
struct DanmakuSession {
    queue: Arc<Mutex<Vec<DanmakuMessage>>>,
    last_active: Instant,
}

/// 直播内核单例。data_dir 下放 silm.json（关注/设置）。
pub struct LiveEngine {
    pub st: Shared,
    /// 活跃弹幕会话：key = platform:room
    sessions: DashMap<String, DanmakuSession>,
    /// 弹幕消息在队列里的上限，超出丢弃最旧
    queue_cap: usize,
}

impl LiveEngine {
    /// 用 data_dir 构建内核；鉴权固定关闭（嵌入式无 HTTP 面板）
    pub async fn open(data_dir: &str) -> anyhow::Result<Self> {
        let mut cfg = Config::default();
        cfg.storage.data_dir = PathBuf::from(data_dir);
        cfg.auth.enabled = false;
        cfg.auth.password.clear();
        let st = AppState::build(cfg).await?;
        Ok(Self { st, sessions: DashMap::new(), queue_cap: 400 })
    }

    // ---------- 平台 ----------

    pub fn sites(&self) -> Value {
        json!({ "sites": self.st.sites.list() })
    }

    pub async fn parse(&self, text: &str) -> ApiResult<Value> {
        match self.st.sites.parse_link(&self.st, text).await {
            Some((platform, room_id)) => Ok(json!({ "platform": platform, "roomId": room_id })),
            None => Err(AppError::bad("无法识别该链接 / 房间号，请检查输入")),
        }
    }

    // ---------- 搜索 ----------

    pub async fn search(&self, platform: &str, kw: &str, page: u32, anchor: bool) -> ApiResult<Value> {
        let site = self.st.sites.site_or_err(platform)?;
        if !site.searchable() {
            return Err(AppError::bad(format!("{}暂不支持搜索", site.name())));
        }
        let r = site.search(&self.st, kw, page.max(1), anchor).await.api("搜索")?;
        Ok(json!({ "hasMore": r.has_more, "items": r.items }))
    }

    // ---------- 房间 ----------

    async fn cached_detail(&self, platform: &str, room: &str) -> ApiResult<RoomDetail> {
        let site = self.st.sites.site_or_err(platform)?;
        let key = RoomCache::key(platform, room);
        if let Some(d) = self.st.cache.get(&key) { return Ok(d); }
        let d = site.room_detail(&self.st, room).await.api("获取房间信息")?;
        self.st.cache.put(key, d.clone());
        Ok(d)
    }

    pub async fn room(&self, platform: &str, room: &str) -> ApiResult<Value> {
        let d = self.cached_detail(platform, room).await?;
        Ok(json!({ "detail": d }))
    }

    /// 播放地址：返回原始流 URL + 平台所需请求头，交给 Flutter 播放器直连。
    /// 每条线路形如 {name,type,url,headers:{referer,user-agent,cookie}}。
    pub async fn play(&self, platform: &str, room: &str) -> ApiResult<Value> {
        let site = self.st.sites.site_or_err(platform)?;
        let detail = self.cached_detail(platform, room).await?;
        let qualities = site.play(&self.st, &detail).await.api("获取播放地址")?;
        let list: Vec<Value> = qualities.iter().map(|q| {
            let lines: Vec<Value> = q.urls.iter().enumerate().map(|(i, u)| {
                let hls = u.contains(".m3u8");
                let mut headers = serde_json::Map::new();
                for (k, v) in &q.headers {
                    let kl = k.to_lowercase();
                    if matches!(kl.as_str(), "referer" | "user-agent" | "cookie") {
                        headers.insert(kl, json!(v));
                    }
                }
                json!({
                    "name": format!("线路 {}", i + 1),
                    "type": if hls { "hls" } else { "flv" },
                    "url": u,
                    "headers": Value::Object(headers),
                })
            }).collect();
            json!({ "name": q.name, "key": q.key, "lines": lines })
        }).collect();
        Ok(json!({
            "qualities": list,
            "danmaku": site.danmaku_supported(),
            "roomId": detail.room_id,
        }))
    }

    pub async fn live_status(&self, platform: &str, room: &str) -> ApiResult<Value> {
        let site = self.st.sites.site_or_err(platform)?;
        let live = site.live_status(&self.st, room).await.api("查询开播状态")?;
        Ok(json!({ "live": live }))
    }

    // ---------- 弹幕轮询 ----------

    /// 连接某房间弹幕：建立上游订阅并常驻采集。重复调用同一房间会先释放旧会话。
    pub async fn danmaku_start(&self, platform: &str, room: &str) -> ApiResult<Value> {
        let key = format!("{platform}:{room}");
        if self.sessions.contains_key(&key) {
            self.sessions.remove(&key);
        }
        let detail = self.cached_detail(platform, room).await?;
        let sub = DanmakuHub::subscribe(
            self.st.danmaku.clone(),
            self.st.clone(),
            platform,
            room,
            detail.danmaku_args,
        ).await.map_err(|e| AppError::internal(e.to_string()))?;
        let queue = Arc::new(Mutex::new(Vec::with_capacity(128)));
        let cap = self.queue_cap;
        // 后台常驻：订阅消息持续写入队列，Dart 侧轮询取走。
        tokio::spawn(Self::run_danmaku_pump(sub, queue.clone(), cap));
        self.sessions.insert(key, DanmakuSession {
            queue,
            last_active: Instant::now(),
        });
        Ok(json!({ "ok": true }))
    }

    /// Dart 侧每 ~250ms 轮询：取走并清空当前消息，返回 {messages:[...]}。
    pub async fn danmaku_poll(&self, platform: &str, room: &str) -> Value {
        let key = format!("{platform}:{room}");
        let Some(mut sess) = self.sessions.get_mut(&key) else {
            return json!({ "messages": [], "connected": false });
        };
        sess.last_active = Instant::now();
        let mut q = sess.queue.lock().await;
        let msgs: Vec<DanmakuMessage> = q.drain(..).collect();
        // 后台 pump 把消息塞进队列：在 start 里已 spawn；这里只负责取走。
        json!({ "messages": msgs, "connected": true })
    }

    pub fn danmaku_stop(&self, platform: &str, room: &str) -> Value {
        let key = format!("{platform}:{room}");
        self.sessions.remove(&key);
        json!({ "ok": true })
    }

    /// 后台采集：把 sub.recv 的消息推入 queue，直到订阅结束。
    async fn run_danmaku_pump(
        mut sub: Subscription,
        queue: Arc<Mutex<Vec<DanmakuMessage>>>,
        cap: usize,
    ) {
        loop {
            match sub.recv().await {
                Some(m) => {
                    let mut q = queue.lock().await;
                    if q.len() >= cap { q.remove(0); }
                    q.push(m);
                }
                None => break,
            }
        }
    }

    // ---------- 关注 ----------

    pub async fn follows(&self) -> Value {
        let items = self.st.store.follows().await;
        // 附带实时开播状态（并发查询，单个失败按离线处理）
        let mut out = Vec::new();
        for f in items {
            let live = match self.st.sites.by_id(&f.platform) {
                Some(site) => site.live_status(&self.st, &f.room_id).await.unwrap_or(false),
                None => false,
            };
            let mut v = serde_json::to_value(&f).unwrap_or(json!({}));
            if let Some(obj) = v.as_object_mut() { obj.insert("live".into(), json!(live)); }
            out.push(v);
        }
        json!({ "items": out })
    }

    pub async fn follow_add(&self, p: &Value) -> ApiResult<Value> {
        let platform = p.get("platform").and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
        let room_id = p.get("roomId").or_else(|| p.get("room_id")).and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
        if room_id.is_empty() { return Err(AppError::bad("房间号不能为空")); }
        self.st.sites.site_or_err(&platform)?;
        let title = p.get("title").and_then(|x| x.as_str()).unwrap_or("");
        let cover = p.get("cover").and_then(|x| x.as_str()).unwrap_or("");
        let user_name = p.get("userName").or_else(|| p.get("user_name")).and_then(|x| x.as_str()).unwrap_or("");
        let f = self.st.store.add(&platform, &room_id, title, cover, user_name).await
            .map_err(|e| AppError::internal(e.to_string()))?;
        self.st.cache.clear();
        Ok(json!({ "item": f }))
    }

    pub async fn follow_del(&self, id: &str) -> ApiResult<Value> {
        self.st.store.remove(id).await.map_err(|e| AppError::internal(e.to_string()))?;
        Ok(json!({ "ok": true }))
    }

    pub async fn follow_top(&self, id: &str, top: bool) -> ApiResult<Value> {
        self.st.store.set_top(id, top).await.map_err(|e| AppError::internal(e.to_string()))?;
        Ok(json!({ "ok": true }))
    }

    pub async fn follows_export(&self) -> Value { self.st.store.export_json().await }

    pub async fn follows_import(&self, v: Value) -> ApiResult<Value> {
        let n = self.st.store.import_json(v).await.map_err(|e| AppError::bad(e.to_string()))?;
        self.st.cache.clear();
        Ok(json!({ "imported": n }))
    }

    // ---------- 设置（Cookie / 弹幕持久化） ----------

    pub async fn settings_get(&self) -> Value {
        let mut s = self.st.store.settings().await;
        // 访问密码不回显
        if let Some(pa) = s.panel_auth.as_mut() { pa.password.clear(); }
        serde_json::to_value(&s).unwrap_or_else(|_| json!({}))
    }

    pub async fn settings_set(&self, v: Value) -> ApiResult<Value> {
        let s: Settings = serde_json::from_value(v).map_err(|e| AppError::bad(e.to_string()))?;
        self.st.store.update_settings(s).await.map_err(|e| AppError::internal(e.to_string()))?;
        self.st.cache.clear();
        Ok(json!({ "ok": true }))
    }
}
