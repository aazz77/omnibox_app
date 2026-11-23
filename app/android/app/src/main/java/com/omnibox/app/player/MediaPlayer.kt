package com.omnibox.app.player

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.ui.PlayerView
import com.omnibox.app.models.DanmuItem
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.compose.runtime.LaunchedEffect

/**
 * Media3 ExoPlayer 播放器封装（替代桌面端 mpv / VLC）。
 * 支持 HLS/MP4/FLV 与自定义请求头。
 */
class MediaPlayerController(private val context: Context) {
    var exoPlayer: ExoPlayer? = null
        private set

    private val _position = MutableStateFlow(0L)
    val position: StateFlow<Long> = _position.asStateFlow()
    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()
    private val _playing = MutableStateFlow(false)
    val playing: StateFlow<Boolean> = _playing.asStateFlow()
    private val _buffering = MutableStateFlow(false)
    val buffering: StateFlow<Boolean> = _buffering.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun open(url: String, headers: Map<String, String> = emptyMap(), autoPlay: Boolean = true) {
        release()
        val httpHeaders = headers.toMutableMap()
        if (!httpHeaders.any { it.key.equals("User-Agent", true) }) {
            httpHeaders["User-Agent"] = "OmniBox/1.0"
        }
        val mediaItem = MediaItem.fromUri(url)
        val factory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(httpHeaders)
        val isHls = url.contains(".m3u8") || url.contains("m3u8?")
        val mediaSource = if (isHls) {
            HlsMediaSource.Factory(factory).createMediaSource(mediaItem)
        } else {
            androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(factory)
                .createMediaSource(mediaItem)
        }
        val p = ExoPlayer.Builder(context).build()
        p.setMediaSource(mediaSource)
        p.prepare()
        p.playWhenReady = autoPlay
        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                _buffering.value = state == Player.STATE_BUFFERING
                _playing.value = state == Player.STATE_READY && p.isPlaying
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) { _playing.value = isPlaying }
            override fun onPlayerError(e: androidx.media3.common.PlaybackException) {
                _error.value = e.message ?: "播放失败"
            }
        })
        exoPlayer = p
        _error.value = null
    }

    fun updatePosition() {
        exoPlayer?.let {
            _position.value = it.currentPosition
            _duration.value = it.duration.takeIf { d -> d > 0 } ?: 0L
        }
    }

    fun playPause() { exoPlayer?.let { if (it.isPlaying) it.pause() else it.play() } }
    fun pause() { exoPlayer?.pause() }
    fun play() { exoPlayer?.play() }
    fun seek(ms: Long) { exoPlayer?.seekTo(ms) }
    fun setVolume(v: Float) { exoPlayer?.volume = v.coerceIn(0f, 1f) }
    fun setSpeed(s: Float) {
        exoPlayer?.setPlaybackParameters(androidx.media3.common.PlaybackParameters(s))
    }

    fun release() {
        exoPlayer?.release()
        exoPlayer = null
        _position.value = 0L
        _duration.value = 0L
        _playing.value = false
    }
}

/**
 * 通用视频播放视图。
 */
@Composable
fun VideoView(
    controller: MediaPlayerController,
    modifier: Modifier = Modifier,
    danmuItems: List<DanmuItem> = emptyList(),
    showDanmu: Boolean = false,
    danmuConfig: com.omnibox.app.core.DanmuConfig = com.omnibox.app.core.DanmuConfig(),
    useController: Boolean = true
) {
    val context = LocalContext.current
    val player = controller.exoPlayer

    // 定时刷新 position（驱动进度条与弹幕）
    LaunchedEffect(controller) {
        while (true) {
            controller.updatePosition()
            delay(50)
        }
    }

    Box(modifier = modifier.background(Color.Black)) {
        if (player != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        this.player = player
                        this.useController = useController
                        setBackgroundColor(android.graphics.Color.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
            if (showDanmu) {
                DanmuCanvas(
                    positionFlow = controller.position,
                    items = danmuItems,
                    config = danmuConfig,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}
