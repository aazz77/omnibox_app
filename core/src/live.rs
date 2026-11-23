//! 直播内核 FFI 适配层：把 crate::live_server::engine::LiveEngine 挂到 omnibox_core 的 ob_call。
//! 全局单例，懒初始化；data_dir 复用主内核环境变量，关注/设置存 <data_dir>/live/silm.json。
//! 全部方法为 async，由外层 ob_call 的 rt.block_on 统一驱动。
use std::sync::OnceLock;

use crate::live_server::engine::LiveEngine;
use serde_json::{json, Value};

static ENGINE: OnceLock<LiveEngine> = OnceLock::new();

fn data_dir() -> std::path::PathBuf {
    std::env::var("DATA_DIR")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("./data"))
        .join("live")
}

/// 懒初始化：首次 live_* 调用时构建（内含 QuickJS 签名线程 + 关注存储）。
async fn engine() -> anyhow::Result<&'static LiveEngine> {
    if let Some(e) = ENGINE.get() { return Ok(e); }
    let dir = data_dir();
    std::fs::create_dir_all(&dir).ok();
    let e = LiveEngine::open(&dir.to_string_lossy()).await?;
    let _ = ENGINE.set(e);
    ENGINE.get().ok_or_else(|| anyhow::anyhow!("直播内核初始化失败"))
}

fn arg(p: &Value, key: &str) -> String {
    p.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string()
}

/// 统一把 Result<Value, AppError> 转成给 Flutter 的 JSON（带 ok 标记）
fn result(r: Result<Value, crate::live_server::error::AppError>) -> Value {
    match r {
        Ok(v) => {
            let mut v = v;
            if let Some(obj) = v.as_object_mut() { obj.insert("ok".into(), json!(true)); }
            v
        }
        Err(e) => json!({ "ok": false, "error": e.to_string() }),
    }
}

/// 分派所有 live_* 方法。params 为方法参数对象。async，由 ob_call 的 rt.block_on 驱动。
pub async fn call(method: &str, p: &Value) -> anyhow::Result<Value> {
    let e = engine().await?;
    Ok(match method {
        "live_sites" => e.sites(),
        "live_parse" => result(e.parse(&arg(p, "text")).await),
        "live_search" => result(e.search(
            &arg(p, "platform"), &arg(p, "kw"),
            p.get("page").and_then(|v| v.as_u64()).unwrap_or(1) as u32,
            p.get("anchor").and_then(|v| v.as_bool()).unwrap_or(false),
        ).await),
        "live_room" => result(e.room(&arg(p, "platform"), &arg(p, "room")).await),
        "live_play" => result(e.play(&arg(p, "platform"), &arg(p, "room")).await),
        "live_status" => result(e.live_status(&arg(p, "platform"), &arg(p, "room")).await),
        "live_danmaku_start" => result(e.danmaku_start(&arg(p, "platform"), &arg(p, "room")).await),
        "live_danmaku_poll" => e.danmaku_poll(&arg(p, "platform"), &arg(p, "room")).await,
        "live_danmaku_stop" => e.danmaku_stop(&arg(p, "platform"), &arg(p, "room")),
        "live_follows" => e.follows().await,
        "live_follow_add" => result(e.follow_add(p).await),
        "live_follow_del" => result(e.follow_del(&arg(p, "id")).await),
        "live_follow_top" => result(e.follow_top(
            &arg(p, "id"), p.get("top").and_then(|v| v.as_bool()).unwrap_or(false),
        ).await),
        "live_follows_export" => e.follows_export().await,
        "live_follows_import" => result(e.follows_import(
            p.get("data").cloned().unwrap_or(json!([])),
        ).await),
        "live_settings_get" => e.settings_get().await,
        "live_settings_set" => result(e.settings_set(p.clone()).await),
        _ => return Err(anyhow::anyhow!("未知直播方法: {method}")),
    })
}
