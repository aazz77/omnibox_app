use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    Unauthorized(String),
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Upstream(String),
    #[error("{0}")]
    Internal(String),
}

pub type ApiResult<T> = std::result::Result<T, AppError>;

impl AppError {
    pub fn upstream<S: Into<String>>(s: S) -> Self { AppError::Upstream(s.into()) }
    pub fn internal<S: Into<String>>(s: S) -> Self { AppError::Internal(s.into()) }
    pub fn bad<S: Into<String>>(s: S) -> Self { AppError::BadRequest(s.into()) }
    pub fn not_found<S: Into<String>>(s: S) -> Self { AppError::NotFound(s.into()) }
}

impl From<anyhow::Error> for AppError {
    fn from(e: anyhow::Error) -> Self { AppError::Internal(e.to_string()) }
}
impl From<reqwest::Error> for AppError {
    fn from(e: reqwest::Error) -> Self { AppError::Upstream(format!("上游请求失败：{e}")) }
}
impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self { AppError::Upstream(format!("上游数据解析失败：{e}")) }
}

impl AppError {
    /// 统一转成给 Flutter 的 JSON 错误对象
    pub fn to_json(&self) -> serde_json::Value { json!({ "error": self.to_string() }) }
}

/// 把内部 anyhow 结果转成 API 结果
pub trait IntoApi<T> {
    fn api(self, prefix: &str) -> ApiResult<T>;
}
impl<T> IntoApi<T> for anyhow::Result<T> {
    fn api(self, prefix: &str) -> ApiResult<T> {
        self.map_err(|e| AppError::Upstream(format!("{prefix}：{e}")))
    }
}
