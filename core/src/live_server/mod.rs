//! 多平台直播聚合内核（已并入 omnibox_core 单 crate）：无 axum / 无端口，业务由 ob_call 经 FFI 调用。
//! 平台站点、弹幕协议、JS 签名引擎全部原样复用自 silm-live-server。

#![allow(dead_code)]

pub mod auth;
pub mod config;
pub mod danmaku;
pub mod engine;
pub mod error;
pub mod http_client;
pub mod identity;
pub mod models;
pub mod pb;
pub mod sign;
pub mod sites;
pub mod state;
pub mod store;
pub mod tars;
pub mod util;
