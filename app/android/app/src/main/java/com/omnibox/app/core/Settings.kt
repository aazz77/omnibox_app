package com.omnibox.app.core

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.io.File

/** 点播弹幕配置 */
data class DanmuConfig(
    val open: Boolean = true,
    val lines: Int = 3,
    val speed: Double = 1.5,
    val size: Double = 0.7,
    val alpha: Double = 0.9,
    val spacing: Int = 8,
    val top: Int = 20,
    val randomColor: Boolean = false,
    val apiBase: String = ""
) {
    fun toJson() = JSONObject().apply {
        put("open", open); put("lines", lines); put("speed", speed); put("size", size)
        put("alpha", alpha); put("spacing", spacing); put("top", top)
        put("randomColor", randomColor); put("apiBase", apiBase)
    }
    companion object {
        fun from(j: JSONObject?) = if (j == null) DanmuConfig() else DanmuConfig(
            open = optBool(j, "open", true),
            lines = optInt(j, "lines", 3).coerceIn(1, 30),
            speed = optDouble(j, "speed", 1.5).coerceIn(0.5, 5.0),
            size = optDouble(j, "size", 0.7).coerceIn(0.4, 2.4),
            alpha = optDouble(j, "alpha", 0.9).coerceIn(0.1, 1.0),
            spacing = optInt(j, "spacing", 8).coerceIn(0, 32),
            top = optInt(j, "top", 20).coerceIn(0, 300),
            randomColor = optBool(j, "randomColor", false),
            apiBase = optStr(j, "apiBase", "")
        )
    }
}

/** 直播弹幕配置 */
data class LiveDanmuConfig(
    val enabled: Boolean = true,
    val fontSize: Int = 22,
    val area: Int = 60,
    val lineGap: Int = 10,
    val itemGap: Int = 64,
    val duration: Double = 9.0,
    val colorMode: String = "platform",
    val color: String = "#ffffff",
    val opacity: Double = 1.0,
    val bold: Boolean = true,
    val stroke: Boolean = true,
    val showUser: Boolean = true
) {
    fun toJson() = JSONObject().apply {
        put("enabled", enabled); put("fontSize", fontSize); put("area", area)
        put("lineGap", lineGap); put("itemGap", itemGap); put("duration", duration)
        put("colorMode", colorMode); put("color", color); put("opacity", opacity)
        put("bold", bold); put("stroke", stroke); put("showUser", showUser)
    }
    companion object {
        fun from(j: JSONObject?) = if (j == null) LiveDanmuConfig() else LiveDanmuConfig(
            enabled = optBool(j, "enabled", true),
            fontSize = optInt(j, "fontSize", 22).coerceIn(12, 48),
            area = optInt(j, "area", 60).coerceIn(20, 100),
            lineGap = optInt(j, "lineGap", 10).coerceIn(0, 40),
            itemGap = optInt(j, "itemGap", 64).coerceIn(0, 300),
            duration = optDouble(j, "duration", 9.0).coerceIn(2.0, 20.0),
            colorMode = optStr(j, "colorMode", "platform").ifEmpty { "platform" },
            color = optStr(j, "color", "#ffffff"),
            opacity = optDouble(j, "opacity", 1.0).coerceIn(0.2, 1.0),
            bold = optBool(j, "bold", true),
            stroke = optBool(j, "stroke", true),
            showUser = optBool(j, "showUser", true)
        )
    }
}

private fun optStr(j: JSONObject, k: String, d: String) = if (j.isNull(k)) d else j.optString(k, d)
private fun optBool(j: JSONObject, k: String, d: Boolean) = if (j.isNull(k)) d else j.optBoolean(k, d)
private fun optInt(j: JSONObject, k: String, d: Int) = if (j.isNull(k)) d else runCatching { j.getInt(k) }.getOrDefault(d)
private fun optDouble(j: JSONObject, k: String, d: Double) = if (j.isNull(k)) d else runCatching { j.getDouble(k) }.getOrDefault(d)

/**
 * 全局应用设置（settings.json 持久化到 App 私有目录）。
 * Android 端播放器统一为 Media3 ExoPlayer，桌面端的 mpv/VLC 选择及硬解码项已移除。
 */
object AppSettings {
    private lateinit var file: File

    private val _preferredQuality = MutableStateFlow("320k")
    val preferredQuality: StateFlow<String> = _preferredQuality
    private val _danmu = MutableStateFlow(DanmuConfig())
    val danmu: StateFlow<DanmuConfig> = _danmu
    private val _showBuiltinIptv = MutableStateFlow(true)
    val showBuiltinIptv: StateFlow<Boolean> = _showBuiltinIptv
    private val _liveQuality = MutableStateFlow("highest")
    val liveQuality: StateFlow<String> = _liveQuality
    private val _liveDanmu = MutableStateFlow(LiveDanmuConfig())
    val liveDanmu: StateFlow<LiveDanmuConfig> = _liveDanmu

    fun init(context: Context) {
        file = File(context.filesDir, "omnibox_data/settings.json")
        file.parentFile?.mkdirs()
        load()
    }

    private fun load() {
        if (!file.exists()) return
        runCatching {
            val j = JSONObject(file.readText())
            _preferredQuality.value = optStr(j, "preferredQuality", "320k").ifEmpty { "320k" }
            _danmu.value = DanmuConfig.from(j.optJSONObject("danmu"))
            _showBuiltinIptv.value = optBool(j, "showBuiltinIptv", true)
            _liveQuality.value = optStr(j, "liveQuality", "highest").ifEmpty { "highest" }
            _liveDanmu.value = LiveDanmuConfig.from(j.optJSONObject("liveDanmu"))
        }
    }

    private fun save() {
        runCatching {
            val j = JSONObject().apply {
                put("preferredQuality", _preferredQuality.value)
                put("danmu", _danmu.value.toJson())
                put("showBuiltinIptv", _showBuiltinIptv.value)
                put("liveQuality", _liveQuality.value)
                put("liveDanmu", _liveDanmu.value.toJson())
            }
            file.writeText(j.toString(2))
        }
    }

    fun setPreferredQuality(v: String) { if (v in musicQualityOptions.map { it.value }) { _preferredQuality.value = v; save() } }
    fun setDanmu(v: DanmuConfig) { _danmu.value = v; save() }
    fun setShowBuiltinIptv(v: Boolean) { _showBuiltinIptv.value = v; save() }
    fun setLiveQuality(v: String) { if (v in listOf("highest", "720p", "lowest")) { _liveQuality.value = v; save() } }
    fun setLiveDanmu(v: LiveDanmuConfig) { _liveDanmu.value = v; save() }

    data class Option(val value: String, val label: String, val desc: String = "")

    val liveQualityOptions = listOf(
        Option("highest", "最高画质", ""),
        Option("720p", "720P 优先", ""),
        Option("lowest", "最低画质", "")
    )
    val musicQualityOptions = listOf(
        Option("128k", "标准 128K", ""),
        Option("320k", "高品质 320K（推荐）", ""),
        Option("flac", "无损 FLAC", ""),
        Option("flac24bit", "Hi-Res", "")
    )

    /** 音乐音质优先级，由高到低 */
    val musicQualityPriority = listOf("flac24bit", "flac", "320k", "128k")

    fun bestQuality(types: List<String>, preference: String): String {
        var start = musicQualityPriority.indexOf(preference)
        if (start < 0) start = musicQualityPriority.indexOf("320k")
        if (start < 0) start = musicQualityPriority.lastIndex
        if (types.isEmpty()) return musicQualityPriority[start]
        for (i in start until musicQualityPriority.size) {
            if (types.contains(musicQualityPriority[i])) return musicQualityPriority[i]
        }
        for (q in musicQualityPriority) if (types.contains(q)) return q
        return types.first()
    }

    fun qualityLabel(q: String) = when (q) {
        "flac24bit" -> "Hi-Res"; "flac" -> "无损"; "320k" -> "高品质"; "128k" -> "标准"; else -> q.uppercase()
    }
}
