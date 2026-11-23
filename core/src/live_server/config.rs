use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub server: ServerConfig,
    #[serde(default)]
    pub auth: AuthConfig,
    #[serde(default)]
    pub storage: StorageConfig,
    #[serde(default)]
    pub upstream: UpstreamConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_listen")]
    pub listen: String,
    /// 静态页面目录。留空则使用内嵌到二进制的页面。
    #[serde(default)]
    pub web_dir: Option<PathBuf>,
    /// 房间详情缓存秒数
    #[serde(default = "default_cache_ttl")]
    pub cache_ttl: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    /// 按需开启；关闭时所有人可直接访问
    #[serde(default)]
    pub enabled: bool,
    /// 面板访问密码
    #[serde(default)]
    pub password: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StorageConfig {
    #[serde(default = "default_data_dir")]
    pub data_dir: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UpstreamConfig {
    /// 所有对外请求的代理，留空直连
    #[serde(default)]
    pub proxy: Option<String>,
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
}

fn default_listen() -> String { "0.0.0.0:8080".into() }
fn default_data_dir() -> PathBuf { PathBuf::from("./data") }
fn default_cache_ttl() -> u64 { 60 }
fn default_timeout() -> u64 { 20 }

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig { listen: default_listen(), web_dir: None, cache_ttl: default_cache_ttl() },
            auth: AuthConfig { enabled: false, password: String::new() },
            storage: StorageConfig { data_dir: default_data_dir() },
            upstream: UpstreamConfig { proxy: None, timeout_secs: default_timeout() },
        }
    }
}
impl Default for ServerConfig { fn default() -> Self { Config::default().server } }
impl Default for AuthConfig { fn default() -> Self { Config::default().auth } }
impl Default for StorageConfig { fn default() -> Self { Config::default().storage } }
impl Default for UpstreamConfig { fn default() -> Self { Config::default().upstream } }
