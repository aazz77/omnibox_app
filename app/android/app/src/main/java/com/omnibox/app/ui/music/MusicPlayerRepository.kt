package com.omnibox.app.ui.music

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.models.LrcLine
import com.omnibox.app.models.MusicSong
import com.omnibox.app.models.parseLrc
import com.omnibox.app.models.str
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class QueueTrack(val song: MusicSong, var quality: String, var url: String? = null)

enum class PlayMode { LIST, SHUFFLE, ONE }

/**
 * 全局音乐播放器：单例，持有唯一 ExoPlayer + 队列。
 * generation 计数防快速切歌串音；音质按偏好 + types 智能降级。
 */
object MusicPlayerRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var player: ExoPlayer? = null
    private var context: Context? = null
    private var generation = 0
    private var readyForCompleted = false

    private val _queue = mutableListOf<QueueTrack>()
    val queue: List<QueueTrack> get() = _queue

    private val _index = MutableStateFlow(-1)
    val index: StateFlow<Int> = _index.asStateFlow()
    private val _playing = MutableStateFlow(false)
    val playing: StateFlow<Boolean> = _playing.asStateFlow()
    private val _position = MutableStateFlow(0L)
    val position: StateFlow<Long> = _position.asStateFlow()
    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()
    private val _volume = MutableStateFlow(100f)
    val volume: StateFlow<Float> = _volume.asStateFlow()
    private val _speed = MutableStateFlow(1f)
    val speed: StateFlow<Float> = _speed.asStateFlow()
    private val _repeatMode = MutableStateFlow(PlayMode.LIST)
    val repeatMode: StateFlow<PlayMode> = _repeatMode.asStateFlow()
    private val _lrcLines = MutableStateFlow<List<LrcLine>>(emptyList())
    val lrcLines: StateFlow<List<LrcLine>> = _lrcLines.asStateFlow()
    private val _lrcIndex = MutableStateFlow(-1)
    val lrcIndex: StateFlow<Int> = _lrcIndex.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _quality = MutableStateFlow("320k")
    val quality: StateFlow<String> = _quality.asStateFlow()
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision.asStateFlow()
    private val _currentSong = MutableStateFlow<MusicSong?>(null)
    val currentSongFlow: StateFlow<MusicSong?> = _currentSong.asStateFlow()

    private var shuffleOrder = listOf<Int>()

    val currentSong: MusicSong? get() = _index.value.takeIf { it in _queue.indices }?.let { _queue[it].song }

    fun init(ctx: Context) {
        if (player != null) return
        context = ctx.applicationContext
        player = ExoPlayer.Builder(ctx.applicationContext).build().apply {
            addListener(object : androidx.media3.common.Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) { _playing.value = isPlaying }
                override fun onPlaybackStateChanged(state: Int) {
                    if (state == androidx.media3.common.Player.STATE_ENDED) onCompleted()
                }
                override fun onPlayerError(e: androidx.media3.common.PlaybackException) {
                    _error.value = e.message
                }
            })
        }
        _ready.value = true
        // 定时更新进度 + 歌词索引
        scope.launch {
            while (true) {
                player?.let { p ->
                    _position.value = p.currentPosition
                    _duration.value = p.duration.takeIf { it > 0 } ?: 0L
                    updateLrcIndex(p.currentPosition)
                }
                delay(200)
            }
        }
    }

    fun playSongs(songs: List<MusicSong>, startIndex: Int) {
        if (songs.isEmpty()) return
        val pref = AppSettings.preferredQuality.value
        _queue.clear()
        _queue.addAll(songs.map { QueueTrack(it, AppSettings.bestQuality(it.types, pref)) })
        _index.value = startIndex.coerceIn(0, _queue.lastIndex)
        buildShuffle()
        _error.value = null
        _revision.value++
        scope.launch { doPlayAt(_index.value) }
    }

    private suspend fun doPlayAt(index: Int) {
        if (index !in _queue.indices) return
        val gen = ++generation
        readyForCompleted = false
        _index.value = index
        _position.value = 0L; _duration.value = 0L
        _lrcIndex.value = -1
        _error.value = null
        val track = _queue[index]
        _currentSong.value = track.song
        _quality.value = track.quality
        try {
            if (track.url == null) {
                val r = Api.call("music_url", mapOf("songInfo" to track.song.toInfo(), "quality" to track.quality))
                val url = r.optString("url")
                if (r.optBoolean("ok") && url.isNotEmpty()) track.url = url
                else throw Exception(r.optString("error", "未找到播放链接，请先导入并启用音源"))
            }
            if (gen != generation) return
            track.url?.let { url ->
                withContext(Dispatchers.Main) {
                    player?.setMediaItem(MediaItem.fromUri(url))
                    player?.prepare()
                    player?.playWhenReady = true
                }
            }
            loadLyric(track.song, gen)
            delay(600)
            if (gen == generation) readyForCompleted = true
        } catch (e: Exception) {
            if (gen == generation) _error.value = e.message
        }
    }

    private suspend fun loadLyric(song: MusicSong, gen: Int) {
        try {
            val r = Api.call("music_lyric", mapOf("songInfo" to song.toInfo()))
            var lyric = r.optString("lyric")
            val trans = r.optString("tlyric")
            if (trans.isNotEmpty() && trans != lyric) lyric = "$lyric\n$trans"
            if (gen == generation) _lrcLines.value = parseLrc(lyric)
        } catch (_: Exception) { }
    }

    private fun updateLrcIndex(posMs: Long) {
        val lines = _lrcLines.value
        if (lines.isEmpty()) { if (_lrcIndex.value != -1) _lrcIndex.value = -1; return }
        var idx = -1
        for (i in lines.indices) if (lines[i].timeMs <= posMs) idx = i else break
        if (idx != _lrcIndex.value) _lrcIndex.value = idx
    }

    private fun buildShuffle() {
        shuffleOrder = _queue.indices.toList().shuffled()
    }

    private fun onCompleted() {
        if (!readyForCompleted || _queue.isEmpty()) return
        readyForCompleted = false
        when (_repeatMode.value) {
            PlayMode.ONE -> scope.launch { doPlayAt(_index.value) }
            PlayMode.SHUFFLE -> {
                val pos = shuffleOrder.indexOf(_index.value)
                val next = if (pos < 0) shuffleOrder.firstOrNull() ?: 0 else shuffleOrder[(pos + 1) % shuffleOrder.size]
                scope.launch { doPlayAt(next) }
            }
            PlayMode.LIST -> scope.launch { doPlayAt((_index.value + 1) % _queue.size) }
        }
    }

    fun playPause() { player?.let { if (it.isPlaying) it.pause() else it.play() } }
    fun pause() { player?.pause() }
    fun seek(ms: Long) { player?.seekTo(ms) }
    fun setVolume(v: Float) { val c = v.coerceIn(0f, 100f); _volume.value = c; player?.volume = c / 100f }
    fun setSpeed(s: Float) { _speed.value = s; player?.setPlaybackParameters(androidx.media3.common.PlaybackParameters(s)) }
    fun next() = scope.launch { doPlayAt(shiftIndex(1)) }
    fun previous() = scope.launch { doPlayAt(shiftIndex(-1)) }

    private fun shiftIndex(dir: Int): Int {
        if (_queue.isEmpty()) return -1
        return when (_repeatMode.value) {
            PlayMode.SHUFFLE -> {
                val pos = shuffleOrder.indexOf(_index.value)
                if (pos < 0) shuffleOrder.first() else shuffleOrder[(pos + dir + shuffleOrder.size) % shuffleOrder.size]
            }
            else -> (_index.value + dir + _queue.size) % _queue.size
        }
    }

    fun playAt(i: Int) { scope.launch { doPlayAt(i) } }

    fun cycleRepeat() {
        _repeatMode.value = when (_repeatMode.value) {
            PlayMode.LIST -> PlayMode.SHUFFLE
            PlayMode.SHUFFLE -> PlayMode.ONE
            PlayMode.ONE -> PlayMode.LIST
        }
        if (_repeatMode.value == PlayMode.SHUFFLE) buildShuffle()
    }

    fun setQuality(q: String) {
        val i = _index.value
        if (i in _queue.indices) {
            _queue[i].quality = q
            _queue[i].url = null
            scope.launch { doPlayAt(i) }
        }
    }

    fun onQualityPreferenceChanged() {
        val pref = AppSettings.preferredQuality.value
        _queue.forEach { t ->
            val best = AppSettings.bestQuality(t.song.types, pref)
            if (best != t.quality) { t.quality = best; t.url = null }
        }
        val i = _index.value
        if (i in _queue.indices && _playing.value) scope.launch { doPlayAt(i) }
    }

    fun release() {
        player?.release()
        player = null
        _ready.value = false
    }
}
