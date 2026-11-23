package com.omnibox.app.core

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.omnibox.app.OmniBoxNative
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * 内核 RPC 统一入口。所有 FFI 调用在 IO 线程执行，避免阻塞 UI。
 */
object Api {
    private var initialized = false

    fun init(dataDir: String) {
        if (initialized) return
        initialized = OmniBoxNative.init(dataDir, "")
    }

    val isInitialized: Boolean get() = initialized

    suspend fun call(method: String, params: Map<String, Any?> = emptyMap()): JSONObject =
        withContext(Dispatchers.IO) {
            val json = JSONObject()
            params.forEach { (k, v) ->
                when (v) {
                    null -> json.put(k, JSONObject.NULL)
                    is List<*> -> json.put(k, JSONArray(v))
                    is Map<*, *> -> json.put(k, JSONObject(v))
                    else -> json.put(k, v)
                }
            }
            val result = OmniBoxNative.call(method, json.toString())
            try {
                JSONObject(result)
            } catch (e: Exception) {
                JSONObject().put("ok", false).put("error", "JSON 解析失败: ${e.message}")
            }
        }

    /** 取图片字节并解码为 Bitmap（ob_img 带防盗链 Referer） */
    suspend fun image(url: String): Bitmap? = withContext(Dispatchers.IO) {
        if (url.isBlank() || (!url.startsWith("http://") && !url.startsWith("https://"))) return@withContext null
        try {
            val arr = OmniBoxNative.image(url) ?: return@withContext null
            if (arr.size < 2) return@withContext null
            val bytes = arr[1] as? ByteArray ?: return@withContext null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (_: Exception) {
            null
        }
    }

    // ===== 常用方法快捷封装 =====
    suspend fun health() = call("health")
    suspend fun doubanHome() = call("douban_home")
    suspend fun doubanCategory(cat: String, page: Int = 1) = call("douban_category", mapOf("cat" to cat, "page" to page))
    suspend fun search(src: String, wd: String, page: Int = 1) =
        call("search", mapOf("src" to src, "wd" to wd, "page" to page))
    suspend fun detail(src: String, id: String) = call("detail", mapOf("src" to src, "id" to id))
    suspend fun play(src: String, q: String) = call("play", mapOf("src" to src, "q" to q))
    suspend fun historyList() = call("history_list")
    suspend fun historyAdd(src: String, id: String, name: String, pic: String, ep: Int, epname: String) =
        call("history_add", mapOf("src" to src, "id" to id, "name" to name, "pic" to pic, "ep" to ep, "epname" to epname))
    suspend fun historyRemove(key: String) = call("history_remove", mapOf("key" to key))
    suspend fun historyClear() = call("history_clear")
    suspend fun spidersList() = call("spiders_list")
    suspend fun spidersAdd(name: String, source: String) = call("spiders_add", mapOf("name" to name, "source" to source))
    suspend fun spidersAddUrl(url: String) = call("spiders_add_url", mapOf("url" to url))
    suspend fun spidersToggle(id: String, enabled: Boolean) = call("spiders_toggle", mapOf("id" to id, "enabled" to enabled))
    suspend fun spidersRemove(id: String) = call("spiders_remove", mapOf("id" to id))
    suspend fun spidersSource(id: String) = call("spiders_source", mapOf("id" to id))
    suspend fun spidersTest(id: String, kw: String = "测试") = call("spiders_test", mapOf("id" to id, "kw" to kw))
    suspend fun danmuSearch(keyword: String, apiBase: String? = null): JSONObject {
        val p = mutableMapOf<String, Any?>("keyword" to keyword)
        if (!apiBase.isNullOrEmpty()) p["api_base"] = apiBase
        return call("danmu_search", p)
    }
    suspend fun danmuLoad(id: String, apiBase: String? = null): JSONObject {
        val p = mutableMapOf<String, Any?>("id" to id)
        if (!apiBase.isNullOrEmpty()) p["api_base"] = apiBase
        return call("danmu_load", p)
    }
}
