package com.omnibox.app.core

import android.content.Context
import com.omnibox.app.models.IptvSource
import com.omnibox.app.models.M3uChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** M3U 解析：属性优先级 tvg-name > title > 逗号后文本；分组用 LinkedHashMap 保序 */
object M3uParser {
    private val attrRegex = Regex("([a-zA-Z0-9_-]+)=\"([^\"]*)\"")

    fun parse(content: String): List<M3uChannel> {
        val text = if (content.startsWith("\uFEFF")) content.substring(1) else content
        val out = mutableListOf<M3uChannel>()
        var name = ""; var group = "未分组"; var logo = ""; var id = ""
        text.lines().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty() || line.equals("#EXTM3U", true)) return@forEach
            if (line.startsWith("#", true)) {
                if (line.startsWith("#EXTINF:", true)) {
                    val attrs = mutableMapOf<String, String>()
                    attrRegex.findAll(line).forEach { attrs[it.groupValues[1].lowercase()] = it.groupValues[2] }
                    val commaName = line.substringAfterLast(",").trim()
                    name = attrs["tvg-name"] ?: attrs["title"] ?: commaName
                    group = attrs["group-title"] ?: "未分组"
                    logo = attrs["tvg-logo"] ?: ""
                    id = attrs["tvg-id"] ?: ""
                }
                return@forEach
            }
            val channelName = name.ifEmpty { guessName(line) }
            out.add(M3uChannel(channelName, line, group, logo, id))
            name = ""; group = "未分组"; logo = ""; id = ""
        }
        return out
    }

    private fun guessName(url: String): String = runCatching {
        val seg = java.net.URI(url).path.trim('/').split('/').lastOrNull().orEmpty()
        seg.split('.').firstOrNull().takeIf { !it.isNullOrEmpty() } ?: url
    }.getOrDefault(url)

    fun groupBy(channels: List<M3uChannel>): LinkedHashMap<String, List<M3uChannel>> {
        val map = LinkedHashMap<String, MutableList<M3uChannel>>()
        channels.forEach { map.getOrPut(it.group) { mutableListOf() }.add(it) }
        return map as LinkedHashMap<String, List<M3uChannel>>
    }
}

/** IPTV 源存储（本地 JSON，等价 Dart IptvStore） */
object IptvStore {
    private lateinit var file: File
    private val _sources = mutableListOf<IptvSource>()
    val sources: List<IptvSource> get() = _sources

    fun init(context: Context) {
        file = File(context.filesDir, "omnibox_data/iptv_sources.json")
        file.parentFile?.mkdirs()
        load()
    }

    private fun load() {
        _sources.clear()
        if (!file.exists()) return
        runCatching {
            val arr = JSONArray(file.readText())
            for (i in 0 until arr.length()) {
                val j = arr.getJSONObject(i)
                _sources.add(IptvSource(
                    name = j.optString("name"),
                    type = j.optString("type", "network"),
                    url = j.optString("url"),
                    filePath = j.optString("filePath"),
                    fileName = j.optString("fileName"),
                    autoUpdate = j.optString("autoUpdate") == "true" || j.optBoolean("autoUpdate")
                ))
            }
        }
    }

    private fun save() {
        val arr = JSONArray()
        _sources.forEach { s ->
            arr.put(JSONObject().apply {
                put("name", s.name); put("type", s.type); put("url", s.url)
                put("filePath", s.filePath); put("fileName", s.fileName)
                put("autoUpdate", s.autoUpdate.toString())
            })
        }
        file.writeText(arr.toString(2))
    }

    fun add(s: IptvSource) { _sources.add(s); save() }
    fun update(index: Int, s: IptvSource) { if (index in _sources.indices) { _sources[index] = s; save() } }
    fun remove(index: Int) { if (index in _sources.indices) { _sources.removeAt(index); save() } }

    suspend fun loadContent(index: Int): String = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val s = _sources[index]
        if (s.isNetwork) {
            val req = java.net.URL(s.url).openConnection() as java.net.HttpURLConnection
            req.connectTimeout = 10000; req.readTimeout = 15000
            req.setRequestProperty("User-Agent", "OmniBox/1.0 (IPTV)")
            req.inputStream.use { it.bufferedReader().readText() }
        } else {
            File(s.filePath).readText()
        }
    }

    suspend fun loadChannels(index: Int): List<M3uChannel> = M3uParser.parse(loadContent(index))
}
