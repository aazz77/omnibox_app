package com.omnibox.app.models

import org.json.JSONArray
import org.json.JSONObject

// ===== 通用 JSON 解析工具：对齐 Dart 侧的宽松取值（pick / toString / 容错） =====

fun JSONObject.str(key: String, fallback: String = ""): String {
    if (isNull(key)) return fallback
    val v = opt(key) ?: return fallback
    val s = v.toString()
    return if (s.isEmpty() || s == "null") fallback else s
}

fun JSONObject.bool(key: String, fallback: Boolean = false): Boolean {
    if (isNull(key)) return fallback
    return when (val v = opt(key)) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.equals("true", ignoreCase = true) || v == "1"
        else -> fallback
    }
}

fun JSONObject.num(key: String, fallback: Double = 0.0): Double {
    if (isNull(key)) return fallback
    return when (val v = opt(key)) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull() ?: fallback
        else -> fallback
    }
}

fun JSONObject.int(key: String, fallback: Int = 0): Int = num(key, fallback.toDouble()).toInt()

fun JSONObject.long(key: String, fallback: Long = 0L): Long = num(key, fallback.toDouble()).toLong()

fun JSONObject.arr(key: String): JSONArray = if (isNull(key)) JSONArray() else optJSONArray(key) ?: JSONArray()

/** JSONArray 的 map 扩展 */
inline fun <T> JSONArray.map(transform: (Any?) -> T): List<T> = (0 until length()).map { transform(opt(it)) }

fun JSONArray.strings(): List<String> = (0 until length()).map { i ->
    val v = opt(i)
    when (v) {
        is String -> v
        is JSONObject -> v.str("name", v.str("keyword", v.str("key", "")))
        else -> v?.toString() ?: ""
    }.takeIf { it.isNotEmpty() } ?: ""
}.filter { it.isNotEmpty() }

// ===== 点播 =====

data class Vod(
    val id: String = "",
    val name: String = "",
    val pic: String = "",
    val remarks: String = "",
    val source: String = ""
) {
    companion object {
        fun from(j: JSONObject) = Vod(
            id = j.str("vod_id", j.str("id")),
            name = j.str("vod_name", j.str("title", "未知")),
            pic = j.str("vod_pic", j.str("pic")),
            remarks = j.str("vod_remarks", j.str("vod_subtitle")),
            source = j.str("source")
        )
    }
}

data class Episode(val name: String, val q: String) {
    companion object {
        fun from(j: JSONObject) = Episode(j.str("name"), j.str("q"))
    }
}

data class VodDetail(
    val vod: Vod,
    val episodes: List<Episode>,
    val desc: String,
    val source: String,
    val year: String = "",
    val area: String = "",
    val actor: String = "",
    val director: String = "",
    val type: String = "",
    val remarks: String = ""
)

data class PlayResult(val url: String, val headers: Map<String, String>)

data class HistoryItem(
    val key: String,
    val src: String,
    val vodId: String,
    val name: String,
    val pic: String,
    val epIndex: Int,
    val epName: String,
    val playedAt: Long
) {
    companion object {
        fun from(j: JSONObject) = HistoryItem(
            key = j.str("key"),
            src = j.str("src"),
            vodId = j.str("vod_id"),
            name = j.str("name"),
            pic = j.str("pic"),
            epIndex = j.int("ep_index"),
            epName = j.str("ep_name"),
            playedAt = j.long("played_at")
        )
    }
}

data class SpiderMeta(
    val id: String,
    val name: String,
    val displayName: String,
    val origin: String,
    val enabled: Boolean,
    val lastError: String?
) {
    companion object {
        fun from(j: JSONObject) = SpiderMeta(
            id = j.str("id"),
            name = j.str("name"),
            displayName = j.str("display_name", j.str("name", j.str("id"))),
            origin = j.str("origin"),
            enabled = j.bool("enabled"),
            lastError = if (j.isNull("last_error")) null else j.str("last_error")
        )
    }
}

data class DanmuItem(val time: Double, val mode: Int, val color: String, val text: String) {
    companion object {
        fun from(j: JSONObject) = DanmuItem(
            time = j.num("time"),
            mode = j.int("mode"),
            color = j.str("color", "#ffffff"),
            text = j.str("text")
        )
    }
}

data class DanmuSearchItem(val id: String, val title: String, val anime: String) {
    companion object {
        fun from(j: JSONObject) = DanmuSearchItem(j.str("id"), j.str("title"), j.str("anime"))
    }
}

// ===== 音乐 =====

data class MusicBoard(val id: String, val name: String, val bangid: String, val source: String) {
    companion object {
        fun from(j: JSONObject) = MusicBoard(
            j.str("id"), j.str("name", "未知榜单"), j.str("bangid"), j.str("source", "kw")
        )
    }
}

data class MusicSong(
    val source: String = "kw",
    val songmid: String = "",
    val name: String = "",
    val singer: String = "",
    val albumName: String = "",
    val albumId: String = "",
    val interval: String = "",
    val hash: String = "",
    val picUrl: String = "",
    val types: List<String> = emptyList(),
    val mv: String = ""
) {
    val uid: String get() = "${source}_${songmid}_$name"
    val mvSupported: Boolean get() = source == "wy" || source == "kg"
    val hasMv: Boolean get() = mvSupported && mv.isNotEmpty() && mv != "0"

    fun toInfo(): JSONObject = JSONObject().apply {
        put("source", source)
        put("songmid", songmid)
        put("songId", songmid)
        put("name", name)
        put("singer", singer)
        put("albumName", albumName)
        put("albumId", albumId)
        put("interval", interval)
        put("hash", hash)
        put("types", org.json.JSONArray(types))
        put("mv", mv)
        if (picUrl.isNotEmpty()) put("picUrl", picUrl)
    }

    companion object {
        private fun pick(j: JSONObject, vararg keys: String): String {
            for (k in keys) {
                if (j.isNull(k)) continue
                val s = j.opt(k)?.toString() ?: continue
                if (s.isNotEmpty() && s != "null") return s
            }
            return ""
        }

        private fun parseTypes(j: JSONObject): List<String> {
            var raw: Any? = null
            for (k in listOf("types", "_types", "qualitys", "_qualitys")) {
                if (j.has(k) && !j.isNull(k)) { raw = j.opt(k); break }
            }
            if (raw == null) {
                val meta = j.optJSONObject("meta")
                if (meta != null) {
                    for (k in listOf("types", "_types", "qualitys", "_qualitys")) {
                        if (meta.has(k) && !meta.isNull(k)) { raw = meta.opt(k); break }
                    }
                }
            }
            val out = mutableListOf<String>()
            when (raw) {
                is JSONArray -> for (i in 0 until raw.length()) {
                    val e = raw.opt(i)
                    if (e is String) out.add(e)
                    else if (e is JSONObject) {
                        val t = pick(e, "type", "name")
                        if (t.isNotEmpty()) out.add(t)
                    }
                }
                is JSONObject -> for (k in raw.keys()) {
                    val v = raw.opt(k)
                    val keep = v == true || (v is Number && v.toDouble() > 0) || v is JSONObject ||
                        (v is String && v.isNotEmpty() && v != "false")
                    if (keep) out.add(k)
                }
            }
            return out.filter { it.isNotEmpty() }
        }

        fun from(j: JSONObject) = MusicSong(
            source = pick(j, "source").ifEmpty { "kw" }.lowercase().removePrefix("kw_"),
            songmid = pick(j, "songmid", "songId", "musicId", "id"),
            name = pick(j, "name", "songName", "title"),
            singer = pick(j, "singer", "artist", "author"),
            albumName = pick(j, "albumName", "album", "album_name"),
            albumId = pick(j, "albumId", "albumMid"),
            interval = pick(j, "interval", "duration"),
            hash = pick(j, "hash"),
            picUrl = pick(j, "picUrl", "img", "pic", "picture"),
            types = parseTypes(j),
            mv = pick(j, "mv", "mvhash", "mvId", "mv_id", "videoId")
        )
    }
}

data class MusicSource(
    val id: String = "",
    val name: String = "未命名音源",
    val description: String = "",
    val version: String = "",
    val author: String = "",
    val homepage: String = "",
    val enabled: Boolean = false,
    val sources: List<String> = emptyList(),
    val size: Int = 0
) {
    companion object {
        fun from(j: JSONObject) = MusicSource(
            id = j.str("id"),
            name = j.str("name", "未命名音源"),
            description = j.str("description"),
            version = j.str("version"),
            author = j.str("author"),
            homepage = j.str("homepage"),
            enabled = j.bool("enabled"),
            sources = j.arr("sources").strings(),
            size = j.int("size")
        )
    }
}

data class LrcLine(val timeMs: Long, val text: String)

fun parseLrc(lrc: String): List<LrcLine> {
    val regex = Regex("\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)")
    val out = mutableListOf<LrcLine>()
    lrc.lines().forEach { line ->
        val m = regex.find(line) ?: return@forEach
        val min = m.groupValues[1].toLongOrNull() ?: return@forEach
        val sec = m.groupValues[2].toLongOrNull() ?: return@forEach
        val msPart = m.groupValues[3]
        val ms = if (msPart.length == 2) msPart.toLongOrNull()?.times(10) ?: 0 else msPart.toLongOrNull() ?: 0
        val text = m.groupValues[4]
        out.add(LrcLine((min * 60 + sec) * 1000 + ms, text))
    }
    return out.sortedBy { it.timeMs }
}

// ===== 直播 =====

data class LiveSite(val id: String, val name: String, val searchable: Boolean, val danmaku: Boolean) {
    companion object {
        fun from(j: JSONObject) = LiveSite(
            j.str("id"), j.str("name"), j.bool("searchable", true), j.bool("danmaku", true)
        )
    }
}

data class LiveSearchItem(
    val roomId: String, val title: String, val userName: String,
    val cover: String, val avatar: String, val online: Long, val liveStatus: Boolean
) {
    companion object {
        fun from(j: JSONObject) = LiveSearchItem(
            j.str("roomId"), j.str("title"), j.str("userName"),
            j.str("cover"), j.str("avatar"), j.long("online"), j.bool("liveStatus")
        )
    }
}

data class LiveFollow(
    val id: String, val platform: String, val roomId: String, val title: String,
    val cover: String, val userName: String, val addTime: Long, val top: Boolean, val live: Boolean
) {
    companion object {
        fun from(j: JSONObject) = LiveFollow(
            j.str("id"), j.str("platform"), j.str("roomId"), j.str("title"),
            j.str("cover"), j.str("userName"), j.long("addTime"), j.bool("top"), j.bool("live")
        )
    }
}

data class LiveLine(val name: String, val type: String, val url: String, val headers: Map<String, String>) {
    companion object {
        fun from(j: JSONObject) = LiveLine(
            j.str("name", "线路"),
            j.str("type", if (j.str("url").contains(".m3u8")) "hls" else "flv"),
            j.str("url"),
            j.optJSONObject("headers")?.let { h -> h.keys().asSequence().associateWith { k -> h.str(k) } } ?: emptyMap()
        )
    }
}

data class LiveQuality(val name: String, val key: String, val lines: List<LiveLine>) {
    companion object {
        fun from(j: JSONObject) = LiveQuality(
            j.str("name"), j.str("key"), j.arr("lines").map { LiveLine.from(it as JSONObject) }
        )
    }
}

data class LivePlayInfo(val qualities: List<LiveQuality>, val danmaku: Boolean, val roomId: String) {
    companion object {
        fun from(j: JSONObject) = LivePlayInfo(
            j.arr("qualities").map { LiveQuality.from(it as JSONObject) },
            j.bool("danmaku"),
            j.str("roomId")
        )
    }
}

data class LiveDanmuMessage(
    val type: String, val userName: String, val message: String, val color: Int, val online: Long
) {
    companion object {
        fun from(j: JSONObject) = LiveDanmuMessage(
            j.str("type", "chat"), j.str("userName"), j.str("message"),
            j.int("color", 0xFFFFFF), j.long("online")
        )
    }
}

// ===== IPTV =====

data class IptvSource(
    val name: String = "",
    val type: String = "network",
    val url: String = "",
    val filePath: String = "",
    val fileName: String = "",
    val autoUpdate: Boolean = false
) {
    val isNetwork: Boolean get() = type == "network"
}

data class M3uChannel(val name: String, val url: String, val group: String, val logo: String, val id: String)
