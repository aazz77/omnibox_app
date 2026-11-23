package com.omnibox.app

/**
 * OmniBox Rust 内核 JNI 绑定。
 * 对应 rust_core/src/jni_bridge.rs 导出的 JNI 方法。
 */
object OmniBoxNative {
    init {
        System.loadLibrary("omnibox_core")
    }

    /** 初始化：设置数据目录与管理员口令，须在其他调用前执行 */
    external fun init(dataDir: String, adminToken: String): Boolean

    /** 通用 RPC：method + params(JSON) -> JSON 字符串 */
    external fun call(method: String, params: String): String

    /**
     * 取图片字节：返回 [mime: String, bytes: ByteArray]，失败返回 null
     */
    external fun image(url: String): Array<Any>?
}
