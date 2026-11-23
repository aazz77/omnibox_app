//! 音乐业务层：编排 JS 引擎（内置 SDK + 用户音源）+ 音源持久化。
//! API 语义对齐 lx-server：榜单/搜索/播放链接/歌词/封面 + 音源管理。
use crate::music_engine::JsHandle;
use crate::music_sources::SourceStore;
use serde_json::{json, Value};
use std::sync::OnceLock;

static ENGINE: OnceLock<JsHandle> = OnceLock::new();
static SOURCES: OnceLock<SourceStore> = OnceLock::new();

fn data_dir() -> std::path::PathBuf {
    std::env::var("DATA_DIR").ok().filter(|s| !s.trim().is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("./data"))
}

/// 初始化音乐引擎与音源库（ob_init 调用一次；失败不 panic，音乐功能降级为空）。
pub fn init() {
    let _ = SOURCES.set(SourceStore::new(data_dir().join("music")).expect("创建音乐数据目录失败"));
    if let Ok((handle, _join)) = crate::music_engine::spawn() {
        let _ = ENGINE.set(handle);
        // 有启用源时加载其脚本进 user 沙箱
        if let Some(store) = SOURCES.get() {
            if let Some((_item, script)) = store.enabled_script_for("__any__") {
                let h = ENGINE.get().unwrap().clone();
                tokio::spawn(async move { let _ = h.load_user(script).await; });
            }
        }
    }
}

fn engine() -> anyhow::Result<&'static JsHandle> {
    ENGINE.get().ok_or_else(|| anyhow::anyhow!("音乐引擎未初始化"))
}
fn store() -> anyhow::Result<&'static SourceStore> {
    SOURCES.get().ok_or_else(|| anyhow::anyhow!("音源库未初始化"))
}

fn qs(v: &Value, k: &str, d: &str) -> String {
    v.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).unwrap_or(d).to_string()
}
fn qi(v: &Value, k: &str, d: i64) -> i64 {
    v.get(k).and_then(Value::as_i64).unwrap_or(d)
}

/// 内置榜单列表
pub async fn boards(p: &Value) -> Value {
    let args = json!({"source": qs(p, "source", "kw")});
    match engine().unwrap().builtin("getBoards", args).await {
        Ok(v) => v,
        Err(e) => json!({"ok": false, "error": e}),
    }
}

/// 榜内歌曲列表
pub async fn board_list(p: &Value) -> Value {
    let args = json!({
        "source": qs(p, "source", "kw"),
        "id": qs(p, "bangid", ""),
        "page": qi(p, "page", 1),
    });
    match engine().unwrap().builtin("boardList", args).await {
        Ok(v) => v,
        Err(e) => json!({"ok": false, "error": e}),
    }
}

/// 搜索（返回 list 数组）
pub async fn search(p: &Value) -> Value {
    let keyword = qs(p, "keyword", "");
    if keyword.trim().is_empty() { return json!({"ok": false, "error": "关键词不能为空", "list": []}); }
    let args = json!({
        "source": qs(p, "source", "kw"),
        "keyword": keyword,
        "page": qi(p, "page", 1),
        "limit": qi(p, "limit", 20),
    });
    match engine().unwrap().builtin("search", args).await {
        Ok(v) => v,
        Err(e) => json!({"ok": false, "error": e, "list": []}),
    }
}

/// 热搜词
pub async fn hot_search(p: &Value) -> Value {
    let args = json!({"source": qs(p, "source", "kw")});
    match engine().unwrap().builtin("hotSearch", args).await {
        Ok(v) => v,
        Err(e) => json!({"ok": false, "error": e}),
    }
}

/// 播放链接：优先用户音源 musicUrl，失败回退内置 SDK
pub async fn music_url(p: &Value) -> Value {
    let song = p.get("songInfo").cloned().unwrap_or(json!({}));
    let quality = qs(p, "quality", "128k");
    let source = qs(&song, "source", "");
    if source.is_empty() { return json!({"ok": false, "error": "Invalid songInfo"}); }

    // 1) 用户音源（若加载了脚本且该源支持此平台）
    let st = match store() { Ok(s) => s, Err(_) => return sdk_url(&song, &quality).await };
    if let Some((_item, _script)) = st.enabled_script_for(&source) {
        let call = json!({
            "source": source,
            "action": "musicUrl",
            "info": {"musicInfo": song.clone(), "type": quality.clone()},
        });
        if let Ok(res) = engine().unwrap().user(call).await {
            let d = &res["data"];
            let url = d["url"].as_str().or_else(|| res["url"].as_str()).unwrap_or("");
            if url.starts_with("http") {
                return json!({
                    "ok": true, "url": url,
                    "type": d["type"].as_str().unwrap_or(&quality),
                    "sourceName": "自定义音源",
                });
            }
        }
    }
    sdk_url(&song, &quality).await
}

async fn sdk_url(song: &Value, quality: &str) -> Value {
    let args = json!({"source": qs(song, "source", ""), "musicInfo": song, "type": quality});
    match engine().unwrap().builtin("musicUrl", args).await {
        Ok(res) => {
            let url = res["url"].as_str().unwrap_or("");
            if url.starts_with("http") {
                json!({"ok": true, "url": url, "type": quality, "sourceName": "内置SDK"})
            } else {
                json!({"ok": false, "error": "未找到可用播放链接"})
            }
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

fn pick_str(v: &Value, keys: &[&str]) -> String {
    for k in keys {
        let x = v.get(*k).or_else(|| v.get("meta").and_then(|m| m.get(*k)));
        if let Some(x) = x {
            match x {
                Value::String(s) if !s.is_empty() && s != "null" => return s.clone(),
                Value::Number(n) => return n.to_string(),
                _ => {}
            }
        }
    }
    String::new()
}

/// 稀疏歌曲信息补齐为 SDK musicInfo
fn normalize_song(song: &Value) -> Value {
    let source = pick_str(song, &["source"]).to_ascii_lowercase();
    let mut songmid = pick_str(song, &["songmid", "songId", "musicId", "id"]);
    let mut hash = pick_str(song, &["hash"]);
    if let Some(rest) = songmid.strip_prefix("kw_") { songmid = rest.to_string(); }
    if source == "kg" && songmid.contains('_') {
        let mut it = songmid.splitn(2, '_');
        let a = it.next().unwrap_or("").to_string();
        let b = it.next().unwrap_or("").to_string();
        songmid = a;
        if hash.is_empty() { hash = b; }
    }
    if source == "kg" && songmid.len() == 32 && hash.is_empty() { hash = songmid.clone(); }
    json!({
        "source": source,
        "songmid": songmid,
        "id": songmid,
        "hash": hash,
        "albumId": pick_str(song, &["albumId", "albumMid"]),
        "audioId": pick_str(song, &["audioId"]),
        "name": pick_str(song, &["name"]),
        "singer": pick_str(song, &["singer"]),
        "albumName": pick_str(song, &["albumName"]),
        // 透传歌曲支持的音质列表，供音源脚本按 type 选链；缺省空数组
        "types": song.get("types").cloned().unwrap_or_else(|| json!([])),
    })
}

/// 歌词：优先用户音源 lyric，回退内置 SDK
pub async fn lyric(p: &Value) -> Value {
    let song = p.get("songInfo").cloned().unwrap_or_else(|| p.clone());
    let source = qs(&song, "source", "kw");
    let st = match store() { Ok(s) => s, Err(_) => return sdk_lyric(&song, &source).await };
    if let Some((_item, _script)) = st.enabled_script_for(&source) {
        let call = json!({
            "source": source,
            "action": "lyric",
            "info": {"musicInfo": normalize_song(&song)},
        });
        if let Ok(res) = engine().unwrap().user(call).await {
            let d = &res["data"];
            if d["lyric"].as_str().is_some() || d["lrc"].as_str().is_some() {
                return json!({
                    "ok": true,
                    "lyric": d["lyric"].as_str().or_else(|| d["lrc"].as_str()).unwrap_or(""),
                    "tlyric": d["tlyric"].as_str().unwrap_or(""),
                });
            }
        }
    }
    sdk_lyric(&song, &source).await
}

async fn sdk_lyric(song: &Value, source: &str) -> Value {
    let args = json!({"source": source, "musicInfo": normalize_song(song)});
    match engine().unwrap().builtin("lyric", args).await {
        Ok(v) => {
            let mut v = v;
            if v.get("ok").is_none() { v["ok"] = json!(true); }
            v
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

/// 封面 URL：现成字段 → 内置 SDK pic → 用户音源 pic
pub async fn pic(p: &Value) -> Value {
    let song = p.get("songInfo").cloned().unwrap_or_else(|| p.clone());
    for k in ["picUrl", "img", "pic", "picture"] {
        if let Some(s) = song.get(k).and_then(Value::as_str) {
            if s.starts_with("http") { return json!({"ok": true, "url": s}); }
        }
    }
    let source = qs(&song, "source", "");
    if source.is_empty() { return json!({"ok": false, "error": "source 为空"}); }
    let ns = normalize_song(&song);
    if let Ok(res) = engine().unwrap().builtin("pic", json!({"source": source, "musicInfo": ns.clone()})).await {
        if let Some(u) = pic_from_result(&res) { return json!({"ok": true, "url": u}); }
    }
    if let Ok(st) = store() {
        if let Some((_item, _script)) = st.enabled_script_for(&source) {
            let call = json!({"source": source, "action": "pic", "info": ns});
            if let Ok(res) = engine().unwrap().user(call).await {
                if let Some(u) = pic_from_result(&res["data"]).or_else(|| pic_from_result(&res)) {
                    return json!({"ok": true, "url": u});
                }
            }
        }
    }
    json!({"ok": false, "error": "未找到封面"})
}

fn pic_from_result(v: &Value) -> Option<String> {
    match v {
        Value::String(s) if s.starts_with("http") => Some(s.clone()),
        Value::Object(_) => pic_from_result(&v["url"]),
        _ => None,
    }
}

// ===== MV（仅内置 SDK 的 wy/kg 支持，走 mvInfo/mvUrl action） =====

/// 单曲 MV 信息补全：内置 SDK 重新拉单曲详情，返回 mv id（无 MV 时空串）。
/// 语义对齐 FMusic：仅 wy/kg；网易数值 0 表示无 MV，归一为空串。
pub async fn mv_info(p: &Value) -> Value {
    let source = qs(p, "source", "").to_ascii_lowercase();
    if source != "wy" && source != "kg" {
        return json!({"ok": true, "mv": ""}); // 其余平台无内置 MV 能力
    }
    let song = p.get("songInfo").cloned().unwrap_or_else(|| p.clone());
    let args = json!({"source": source, "musicInfo": normalize_song(&song)});
    match engine().unwrap().builtin("mvInfo", args).await {
        Ok(v) => {
            let mv = v["mv"].as_str().unwrap_or("");
            // 网易无 MV 存数值 0（SDK 已归一为空串，这里再兜底一次）
            let mv = if mv == "0" { "" } else { mv };
            json!({"ok": true, "mv": mv})
        }
        Err(e) => json!({"ok": false, "error": e, "mv": ""}),
    }
}

/// MV 播放直链：内置 SDK 直连（酷狗 m.kugou.com、网易 weapi），不依赖用户音源。
pub async fn mv_url(p: &Value) -> Value {
    let source = qs(p, "source", "").to_ascii_lowercase();
    let mv_id = qs(p, "mvId", "");
    if source != "wy" && source != "kg" {
        return json!({"ok": false, "error": "仅网易云/酷狗支持 MV 播放"});
    }
    if mv_id.is_empty() || mv_id == "0" {
        return json!({"ok": false, "error": "该歌曲没有 MV"});
    }
    let args = json!({"source": source, "mvId": mv_id});
    match engine().unwrap().builtin("mvUrl", args).await {
        Ok(v) => {
            let url = v["url"].as_str().unwrap_or("");
            if url.starts_with("http") {
                json!({"ok": true, "url": url})
            } else {
                json!({"ok": false, "error": "未找到 MV 播放链接"})
            }
        }
        Err(e) => json!({"ok": false, "error": e}),
    }
}

// ===== 音源管理 =====

pub fn source_list() -> Value {
    match store() {
        Ok(s) => json!({"ok": true, "list": s.enrich()}),
        Err(e) => json!({"ok": false, "error": e.to_string(), "list": []}),
    }
}

pub async fn source_add(p: &Value) -> Value {
    let source = qs(p, "source", "");
    if source.trim().is_empty() { return json!({"ok": false, "error": "源码不能为空"}); }
    let url = qs(p, "url", "");
    let enable = p.get("enable").and_then(Value::as_bool).unwrap_or(true);
    let platforms: Vec<String> = p.get("sources").and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let st = match store() { Ok(s) => s, Err(e) => return json!({"ok": false, "error": e.to_string()}) };
    match st.add(&source, &url, &platforms, enable) {
        Ok((id, outcome)) => {
            // 若启用，重新加载 user 沙箱
            if enable {
                if let Some((_item, script)) = st.enabled_script_for("__any__") {
                    if let Some(h) = ENGINE.get() { let _ = h.load_user(script).await; }
                }
            }
            let outcome_s = match outcome {
                crate::music_sources::AddOutcome::Added => "added",
                crate::music_sources::AddOutcome::Updated => "updated",
                crate::music_sources::AddOutcome::Duplicate => "duplicate",
            };
            json!({"ok": true, "id": id, "outcome": outcome_s, "metadata": crate::music_sources::SourceStore::metadata(&source)})
        }
        Err(e) => json!({"ok": false, "error": e.to_string()}),
    }
}

pub async fn source_toggle(p: &Value) -> Value {
    let id = qs(p, "id", "");
    let on = p.get("enabled").and_then(Value::as_bool).unwrap_or(true);
    let st = match store() { Ok(s) => s, Err(e) => return json!({"ok": false, "error": e.to_string()}) };
    if let Err(e) = st.set_enabled(&id, on) { return json!({"ok": false, "error": e.to_string()}); }
    // 重载 user 沙箱
    if let Some(h) = ENGINE.get() {
        if on {
            if let Some((_item, script)) = st.enabled_script_for("__any__") { let _ = h.load_user(script).await; }
            else { let _ = h.unload_user().await; }
        } else {
            let _ = h.unload_user().await;
        }
    }
    json!({"ok": true, "list": st.enrich()})
}

pub fn source_remove(p: &Value) -> Value {
    let id = qs(p, "id", "");
    match store() {
        Ok(s) => match s.remove(&id) {
            Ok(_) => json!({"ok": true, "list": s.enrich()}),
            Err(e) => json!({"ok": false, "error": e.to_string()}),
        },
        Err(e) => json!({"ok": false, "error": e.to_string()}),
    }
}

pub fn source_content(p: &Value) -> Value {
    let id = qs(p, "id", "");
    match store() {
        Ok(s) => match s.source(&id) {
            Some(script) => json!({"ok": true, "source": script}),
            None => json!({"ok": false, "error": "音源不存在"}),
        },
        Err(e) => json!({"ok": false, "error": e.to_string()}),
    }
}

/// 从 URL 拉取音源脚本（用于网络导入）
pub async fn source_import_url(p: &Value) -> Value {
    let url = qs(p, "url", "");
    if !url.starts_with("http") { return json!({"ok": false, "error": "URL 非法"}); }
    let client = match reqwest::Client::builder().timeout(std::time::Duration::from_secs(20))
        .user_agent("Mozilla/5.0").build() {
        Ok(c) => c, Err(e) => return json!({"ok": false, "error": e.to_string()}),
    };
    let text = match client.get(&url).send().await {
        Ok(r) => match r.text().await { Ok(t) => t, Err(e) => return json!({"ok": false, "error": e.to_string()}) },
        Err(e) => return json!({"ok": false, "error": e.to_string()}),
    };
    if text.trim().is_empty() || text.len() > 2_000_000 { return json!({"ok": false, "error": "脚本为空或过大"}); }
    let mut add = p.clone();
    if add.get("source").is_none() { add["source"] = json!(text); }
    source_add(&add).await
}
