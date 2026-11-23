//! 内置央视频源（yspl）FFI 包装。
//! 惰性启动内嵌本地服务（127.0.0.1 随机端口），仅监听回环。
//! 方法（由 lib.rs 分派）：
//!   iptv_yspl_channels   -> 静态 64 频道表（slug/name/group/tvgId/logo）
//!   iptv_yspl_port       -> 启动服务并返回端口（第一次调用会拉起服务）

use serde_json::{json, Value};

fn data_dir() -> String {
    std::env::var("DATA_DIR").unwrap_or_else(|_| "./data".to_string())
}

/// 同步入口：从 lib.rs 的 block_on 内调用（yspl::start 是 async）
pub async fn call(method: &str, params: &Value) -> Value {
    match method {
        "iptv_yspl_channels" => crate::yspl::engine_api::channels(),

        "iptv_yspl_port" => {
            // 支持强制重启（调试用）：params.restart=true
            let restart = params.get("restart").and_then(|v| v.as_bool()).unwrap_or(false);
            if restart {
                // yspl 不提供 stop，重建进程即可；这里仅返回当前端口
            }
            match crate::yspl::engine_api::start(&data_dir()).await {
                Ok(port) => json!({ "ok": true, "port": port }),
                Err(e) => json!({ "ok": false, "error": e }),
            }
        }

        _ => json!({ "ok": false, "error": format!("未知 iptv_yspl 方法: {method}") }),
    }
}
