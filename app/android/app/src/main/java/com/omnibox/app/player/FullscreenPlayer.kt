package com.omnibox.app.player

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.DanmuConfig
import com.omnibox.app.models.DanmuItem

private fun Context.findActivity(): Activity? {
    var ctx = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

private fun hideSystemBars(activity: Activity) {
    val window = activity.window
    WindowCompat.setDecorFitsSystemWindows(window, false)
    WindowInsetsControllerCompat(window, window.decorView).apply {
        hide(WindowInsetsCompat.Type.systemBars())
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}

private fun showSystemBars(activity: Activity) {
    val window = activity.window
    WindowCompat.setDecorFitsSystemWindows(window, true)
    WindowInsetsControllerCompat(window, window.decorView).show(WindowInsetsCompat.Type.systemBars())
}

private fun fmtTime(ms: Long): String {
    val t = ms / 1000
    return "%02d:%02d".format(t / 60, t % 60)
}

/**
 * 横屏全屏播放弹窗：隐藏状态栏与底部手势条，复用传入的 controller（播放器实例不变，进度连续）。
 * 进入时强制横屏，退出时恢复原方向。页面内的 VideoView 应在全屏期间停止渲染，避免两个 PlayerView 争用同一 player。
 */
@Composable
fun FullscreenVideoDialog(
    controller: MediaPlayerController,
    title: String = "",
    showDanmu: Boolean = false,
    danmuItems: List<DanmuItem> = emptyList(),
    danmuConfig: DanmuConfig = DanmuConfig(),
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val activity = context.findActivity()

    DisposableEffect(Unit) {
        val original = activity?.requestedOrientation
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        if (activity != null) hideSystemBars(activity)
        onDispose {
            activity?.requestedOrientation = original ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            if (activity != null) showSystemBars(activity)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
            dismissOnBackPress = true,
            dismissOnClickOutside = false
        )
    ) {
        val position by controller.position.collectAsStateWithLifecycle()
        val duration by controller.duration.collectAsStateWithLifecycle()
        val playing by controller.playing.collectAsStateWithLifecycle()
        var controls by remember { mutableStateOf(true) }

        Box(
            Modifier
                .fillMaxSize()
                .clickable { controls = !controls }
        ) {
            VideoView(
                controller = controller,
                modifier = Modifier.fillMaxSize(),
                danmuItems = danmuItems,
                showDanmu = showDanmu,
                danmuConfig = danmuConfig,
                useController = false
            )

            if (controls) {
                // 顶部：标题 + 退出全屏
                Row(
                    Modifier
                        .fillMaxWidth()
                        .align(Alignment.TopStart)
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        title,
                        color = Color.White,
                        modifier = Modifier.weight(1f),
                        maxLines = 1
                    )
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.FullscreenExit, "退出全屏", tint = Color.White)
                    }
                }

                // 底部：播放/暂停 + 进度 + 时间
                Row(
                    Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomStart)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { controller.playPause() }) {
                        Icon(
                            if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            "播放/暂停",
                            tint = Color.White,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                    Text(fmtTime(position), color = Color.White)
                    Slider(
                        value = if (duration > 0) position.toFloat() else 0f,
                        onValueChange = { controller.seek(it.toLong()) },
                        valueRange = 0f..(duration.coerceAtLeast(1).toFloat()),
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 8.dp)
                    )
                    Text(fmtTime(duration), color = Color.White)
                }
            }
        }
    }
}
