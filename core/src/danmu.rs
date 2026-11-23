// danmu.rs —— 弹幕数据源：弹弹play 兼容 API（插件 Danmu Anywhere 同款镜像）。
// 供 Flutter 播放页弹幕搜索/加载使用。两条 FFI 命令：
//   danmu_search  {keyword, api_base?} -> {ok, list:[{id, title, anime}]}
//   danmu_load    {id, api_base?}      -> {ok, list:[{time, mode, color, text}]}
//
// 语义对齐插件 bg.js：
//   - 搜索：先 search/episodes，空则退化 search/anime 取首部再 bangumi 取剧集
//   - 弹幕：comment/{id}?format=json，p="time,mode,color,uid" 或 B站式 "time,mode,size,color"
//     mode 1~3 滚动 / 4 底部 / 5 顶部，其余丢弃；颜色启发式判位并规范化为 #rrggbb

use serde_json::{json, Value};
use std::time::Duration;

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
/// 插件 danmu-anywhere 使用的默认镜像（弹弹play 兼容 API）
pub const DEFAULT_API_BASE: &str = "https://logvardanmu.konfan.cn";

fn client() -> &'static reqwest::Client {
    static CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .user_agent(UA)
            .build()
            .expect("构建弹幕 HTTP 客户端失败")
    })
}

/// 归一化 api_base：去尾部斜杠，空则用默认镜像
fn base_of(api_base: Option<&str>) -> String {
    let s = api_base.unwrap_or("").trim().trim_end_matches('/');
    if s.is_empty() {
        DEFAULT_API_BASE.to_string()
    } else {
        s.to_string()
    }
}

async fn get_json(url: &str) -> anyhow::Result<Value> {
    let resp = client().get(url).send().await?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {}", resp.status());
    }
    Ok(resp.json::<Value>().await?)
}

/// 颜色位识别：#rrggbb / 0xRRGGBB / 十进制 0..0xffffff 均视为颜色值
fn is_color_value(s: &str) -> bool {
    let t = s.trim();
    if t.is_empty() {
        return false;
    }
    if t.starts_with('#') || t.to_ascii_lowercase().starts_with("0x") {
        return true;
    }
    if !t.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    t.parse::<u64>().map(|n| n <= 0x00ff_ffff).unwrap_or(false)
}

fn normalize_color(s: &str) -> String {
    let t = s.trim();
    if t.starts_with('#') {
        return t.to_string();
    }
    let low = t.to_ascii_lowercase();
    if let Some(hex) = low.strip_prefix("0x") {
        let n = u32::from_str_radix(hex, 16).unwrap_or(0) & 0x00ff_ffff;
        return format!("#{:06x}", n);
    }
    let n = t.parse::<u32>().unwrap_or(0) & 0x00ff_ffff;
    format!("#{:06x}", n)
}

/// 把 episodes + anime 标题扁平化为 [{id,title,anime}]
fn flatten(data: &Value) -> Vec<Value> {
    let mut out = Vec::new();
    let mut push_eps = |eps: Option<&Vec<Value>>, anime_title: &str| {
        if let Some(eps) = eps {
            for ep in eps {
                let id = ep.get("episodeId").or_else(|| ep.get("id"));
                let id = match id {
                    Some(v) => v.as_u64().map(|n| n.to_string()).unwrap_or_else(|| v.to_string()),
                    None => continue,
                };
                let ep_title = ep
                    .get("episodeTitle")
                    .or_else(|| ep.get("title"))
                    .or_else(|| ep.get("name"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let title = if anime_title.is_empty() {
                    ep_title.to_string()
                } else {
                    format!("{} {}", anime_title, ep_title)
                };
                out.push(json!({"id": id, "title": title, "anime": anime_title}));
            }
        }
    };

    // episodes 搜索结果：animes[].episodes
    if let Some(animes) = data.get("animes").or_else(|| data.get("anime")).or_else(|| data.get("data")) {
        if let Some(arr) = animes.as_array() {
            for anime in arr {
                let title = anime
                    .get("animeTitle")
                    .or_else(|| anime.get("title"))
                    .or_else(|| anime.get("name"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                push_eps(anime.get("episodes").and_then(Value::as_array), title);
                if let Some(bangumi) = anime.get("bangumi") {
                    push_eps(bangumi.get("episodes").and_then(Value::as_array), title);
                }
            }
        }
    }
    // bangumi 详情结果：bangumi.episodes
    if let Some(bangumi) = data.get("bangumi") {
        let title = bangumi
            .get("animeTitle")
            .or_else(|| bangumi.get("title"))
            .and_then(Value::as_str)
            .unwrap_or("");
        push_eps(bangumi.get("episodes").and_then(Value::as_array), title);
    }
    out
}

/// 搜索剧集。返回扁平化剧集列表。
pub async fn search(keyword: &str, api_base: Option<&str>) -> anyhow::Result<Value> {
    let kw = keyword.trim();
    if kw.is_empty() {
        anyhow::bail!("关键词不能为空");
    }
    let base = base_of(api_base);

    // 1) 直接搜剧集
    let url = format!(
        "{}/api/v2/search/episodes?anime={}",
        base,
        urlencoding::encode(kw)
    );
    let mut list = match get_json(&url).await {
        Ok(data) => flatten(&data),
        Err(_) => Vec::new(),
    };

    // 2) 退化：先搜番剧，取首部 bangumi 详情再扁平化
    if list.is_empty() {
        let anime_url = format!(
            "{}/api/v2/search/anime?keyword={}",
            base,
            urlencoding::encode(kw)
        );
        if let Ok(data) = get_json(&anime_url).await {
            let animes = data
                .get("animes")
                .or_else(|| data.get("anime"))
                .or_else(|| data.get("data"))
                .and_then(Value::as_array);
            if let Some(first) = animes.and_then(|a| a.first()) {
                let id = first
                    .get("animeId")
                    .or_else(|| first.get("id"))
                    .and_then(|v| v.as_u64().map(|n| n.to_string()));
                if let Some(id) = id {
                    let bg_url = format!("{}/api/v2/bangumi/{}", base, id);
                    if let Ok(bg) = get_json(&bg_url).await {
                        list = flatten(&bg);
                    }
                }
            }
        }
    }
    Ok(json!({"ok": true, "list": list}))
}

/// 加载某集弹幕，返回按时间排序的 [{time, mode, color, text}]。
pub async fn load(id: &str, api_base: Option<&str>) -> anyhow::Result<Value> {
    let id = id.trim();
    if id.is_empty() {
        anyhow::bail!("episode id 不能为空");
    }
    let base = base_of(api_base);
    let url = format!("{}/api/v2/comment/{}?format=json", base, id);
    let data = get_json(&url).await?;
    let comments = data
        .get("comments")
        .or_else(|| data.get("data"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut items: Vec<(f64, Value)> = Vec::new();
    for c in comments {
        let p = c.get("p").and_then(Value::as_str).unwrap_or("");
        let text = c
            .get("m")
            .or_else(|| c.get("text"))
            .and_then(Value::as_str)
            .unwrap_or("");
        if p.is_empty() || text.is_empty() {
            continue;
        }
        let v: Vec<&str> = p.split(',').collect();
        if v.len() < 4 {
            continue;
        }
        let time = v[0].trim().parse::<f64>().unwrap_or(-1.0);
        let mode = v[1].trim().parse::<i64>().unwrap_or(0);
        if !time.is_finite() || time < 0.0 || !(1..=5).contains(&mode) {
            continue;
        }
        // 颜色可能在第 3 或第 4 位（B站式 size 在第 3 位）
        let color = if is_color_value(v[2]) {
            normalize_color(v[2])
        } else if is_color_value(v[3]) {
            normalize_color(v[3])
        } else {
            "#ffffff".to_string()
        };
        items.push((
            time,
            json!({"time": time, "mode": mode, "color": color, "text": text}),
        ));
    }
    items.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    let list: Vec<Value> = items.into_iter().map(|(_, v)| v).collect();
    Ok(json!({"ok": true, "count": list.len(), "list": list}))
}
