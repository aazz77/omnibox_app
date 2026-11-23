//! 精简鉴权状态（嵌入式内核，无 HTTP 服务）：仅保留 state 需要的运行时状态读写。
use std::sync::{Arc, RwLock};

use crate::live_server::config::AuthConfig;
use crate::live_server::util::{random_hex, sha256_hex};

#[allow(dead_code)]
pub const COOKIE_NAME: &str = "silm_session";

struct AuthInner {
    enabled: bool,
    password: String,
    token: String,
}

#[derive(Clone)]
pub struct Auth {
    secret: String,
    inner: Arc<RwLock<AuthInner>>,
}

impl Auth {
    pub fn new(cfg: &AuthConfig) -> Self {
        let secret = random_hex(32);
        let enabled = cfg.enabled && !cfg.password.trim().is_empty();
        let token = Self::derive(&secret, &cfg.password);
        Self {
            secret,
            inner: Arc::new(RwLock::new(AuthInner { enabled, password: cfg.password.clone(), token })),
        }
    }

    fn derive(secret: &str, password: &str) -> String {
        sha256_hex(&format!("{secret}:{password}"))
    }

    pub fn enabled(&self) -> bool {
        self.inner.read().map(|i| i.enabled).unwrap_or(false)
    }

    pub fn has_password(&self) -> bool {
        self.inner.read().map(|i| !i.password.trim().is_empty()).unwrap_or(false)
    }

    pub fn password(&self) -> String {
        self.inner.read().map(|i| i.password.clone()).unwrap_or_default()
    }

    #[allow(dead_code)]
    pub fn cookie(&self) -> String {
        self.inner.read().map(|i| i.token.clone()).unwrap_or_default()
    }

    pub fn update(&self, enabled: bool, password: &str) -> Result<(), String> {
        if enabled && password.trim().is_empty() {
            return Err("开启访问验证时必须设置访问密码".into());
        }
        let token = Self::derive(&self.secret, password);
        let mut inner = self.inner.write().map_err(|_| "鉴权状态更新失败".to_string())?;
        inner.enabled = enabled;
        inner.password = password.to_string();
        inner.token = token;
        Ok(())
    }
}
