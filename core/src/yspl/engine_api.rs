//! 供 omnibox_core 通过 FFI 使用的高层 API。
//! 把 yspl 作为内嵌本地服务拉起（127.0.0.1 + 随机端口），仅暴露：
//!   - start(data_dir) -> port：惰性启动
//!   - port() -> 当前端口（未启动返回 0）
//!   - channels() -> 64 频道 JSON（纯静态表，不需要服务）
//! 伴生引擎（Node /engine_proxy）禁用：no_engine=true，主链路 JCE/bk 取流不需要它。

use std::net::SocketAddr;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;

use crate::yspl::resolver::Resolver;
use crate::yspl::state::AppState;
use crate::yspl::util::log;

/// 已启动服务的实际端口（0 = 未启动）
static PORT: AtomicU16 = AtomicU16::new(0);
/// 是否已发起启动（避免重复 spawn）
static STARTED: AtomicU16 = AtomicU16::new(0);

fn build_cli(data_dir: &str) -> crate::yspl::Cli {
    crate::yspl::Cli {
        port: 0, // serve_with_listener 用已绑定 listener，此值仅作占位
        bind: "127.0.0.1".to_string(),
        data_dir: data_dir.to_string(),
        cache_mb: 200,
        no_4k: false,
        only_4k: false,
        links_per_device: 6,
        zap_debounce: 10.0,
        engine_port: 0,
        timeout: 10.0,
        no_engine: true,
    }
}

/// 惰性启动内嵌服务。重复调用安全（只启动一次）。
/// 必须在 tokio runtime 内调用。返回实际监听端口。
pub async fn start(data_dir: &str) -> Result<u16, String> {
    if STARTED.swap(1, Ordering::SeqCst) == 1 {
        // 等待首次启动完成（PORT 被写入）
        for _ in 0..100 {
            let p = PORT.load(Ordering::SeqCst);
            if p != 0 {
                return Ok(p);
            }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
        let p = PORT.load(Ordering::SeqCst);
        if p != 0 {
            return Ok(p);
        }
        // 首次启动失败，允许重试
        STARTED.store(0, Ordering::SeqCst);
    }

    // 确保 data_dir 存在
    let dd = std::path::PathBuf::from(data_dir).join("yspl");
    if let Err(e) = std::fs::create_dir_all(&dd) {
        STARTED.store(0, Ordering::SeqCst);
        return Err(format!("创建 yspl 数据目录失败: {e}"));
    }

    let cli = build_cli(&dd.to_string_lossy());
    let app = Arc::new(AppState::new(cli));
    let resolver = Resolver::new(app.clone()).map_err(|e| format!("yspl resolver 初始化失败: {e}"))?;
    *app.resolver.write() = Some(resolver.clone());
    resolver.start_background();

    let addr: SocketAddr = "127.0.0.1:0".parse().unwrap();
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| format!("yspl 绑定端口失败: {e}"))?;
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    log(format!("[yspl] 内嵌服务已启动 127.0.0.1:{port}"), 0.0);
    PORT.store(port, Ordering::SeqCst);

    tokio::spawn(async move {
        if let Err(e) = crate::yspl::server::serve_with_listener(app, listener).await {
            log(format!("[yspl] 服务异常退出: {e}"), 0.0);
            // 服务挂了，重置状态以便下次重启
            PORT.store(0, Ordering::SeqCst);
            STARTED.store(0, Ordering::SeqCst);
        }
    });
    Ok(port)
}

/// 当前服务端口，0 = 未启动
pub fn port() -> u16 {
    PORT.load(Ordering::SeqCst)
}

/// 静态频道表（不需要服务即可返回）。
/// 字段：slug / name / group（央视|卫视）/ tvgId / logo / 播放地址模板由 Flutter 用 port 拼。
pub fn channels() -> serde_json::Value {
    let dir = crate::yspl::channels::ChannelDirectory::new();
    let list: Vec<serde_json::Value> = dir
        .unique_channels()
        .into_iter()
        .map(|m| {
            serde_json::json!({
                "slug": m.slug,
                "name": m.name,
                "group": m.group,
                "tvgId": m.tvg_id,
                "logo": m.logo,
            })
        })
        .collect();
    serde_json::json!({ "ok": true, "channels": list, "count": list.len() })
}
