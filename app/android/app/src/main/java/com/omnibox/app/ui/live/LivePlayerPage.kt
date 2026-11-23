package com.omnibox.app.ui.live

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.models.LiveDanmuMessage
import com.omnibox.app.models.LivePlayInfo
import com.omnibox.app.player.FullscreenVideoDialog
import com.omnibox.app.player.MediaPlayerController
import com.omnibox.app.player.VideoView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun LivePlayerPage(platform: String, roomId: String, title: String, userName: String, onBack: () -> Unit) {
    var info by remember { mutableStateOf<LivePlayInfo?>(null) }
    var qi by remember { mutableStateOf(0) }
    var li by remember { mutableStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var danmuOn by remember { mutableStateOf(true) }
    var followed by remember { mutableStateOf(false) }
    var danmuMessages by remember { mutableStateOf<List<LiveDanmuMessage>>(emptyList()) }
    var fullscreen by remember { mutableStateOf(false) }
    var tab by remember { mutableStateOf(0) }
    val danmuCfg by AppSettings.liveDanmu.collectAsStateWithLifecycle()

    val appContext = androidx.compose.ui.platform.LocalContext.current
    val controller = remember { MediaPlayerController(appContext) }
    val scope = rememberCoroutineScope()

    fun openStream() {
        val inf = info ?: return
        val quality = inf.qualities.getOrNull(qi) ?: return
        val line = quality.lines.getOrNull(li) ?: return
        controller.open(line.url, line.headers)
    }

    LaunchedEffect(Unit) {
        val r = Api.call("live_play", mapOf("platform" to platform, "room" to roomId))
        if (!r.optBoolean("ok")) {
            error = r.optString("error", "未获取到播放地址（房间可能未开播）")
            loading = false
            return@LaunchedEffect
        }
        val inf = LivePlayInfo.from(r)
        info = inf
        qi = when (AppSettings.liveQuality.value) {
            "lowest" -> inf.qualities.lastIndex.coerceAtLeast(0)
            "720p" -> inf.qualities.indexOfFirst { it.name.contains("720") || it.key.contains("720") }.takeIf { it >= 0 } ?: 0
            else -> 0
        }
        openStream()
        danmuOn = inf.danmaku && danmuCfg.enabled
        loading = false
        if (inf.danmaku) {
            Api.call("live_danmaku_start", mapOf("platform" to platform, "room" to roomId))
            while (danmuOn) {
                val pr = Api.call("live_danmaku_poll", mapOf("platform" to platform, "room" to roomId))
                val msgs = pr.optJSONArray("messages")?.let { arr ->
                    (0 until arr.length()).map { LiveDanmuMessage.from(arr.getJSONObject(it)) }
                } ?: emptyList()
                if (msgs.isNotEmpty()) danmuMessages = (danmuMessages + msgs).takeLast(100)
                delay(250)
            }
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            scope.launch { Api.call("live_danmaku_stop", mapOf("platform" to platform, "room" to roomId)) }
            controller.release()
        }
    }

    val quality = info?.qualities?.getOrNull(qi)

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        // 顶部标题栏
        Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回") }
            Text(title.ifEmpty { userName }, style = MaterialTheme.typography.titleMedium,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            IconButton(onClick = { danmuOn = !danmuOn }) {
                Text("弹", color = if (danmuOn) MaterialTheme.colorScheme.primary else Color.Gray, fontWeight = FontWeight.Bold)
            }
            IconButton(onClick = {}) { Icon(Icons.Filled.MoreVert, "更多") }
        }

        // 视频区（16:9）
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Color.Black)) {
            if (info != null && !loading && !fullscreen) VideoView(controller, Modifier.fillMaxSize())
            if (loading) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
            error?.let { Text(it, color = Color.White, modifier = Modifier.align(Alignment.Center).padding(16.dp)) }
            IconButton(onClick = { if (info != null) fullscreen = true }, modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp)) {
                Icon(Icons.Filled.Fullscreen, "全屏", tint = Color.White)
            }
        }

        // 主播信息
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(Color(0xFFE8E8F0)), contentAlignment = Alignment.Center) {
                Text(userName.take(1).ifEmpty { "主" }, fontWeight = FontWeight.Bold, color = Color(0xFF7B1FA2))
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(userName.ifEmpty { title }, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(platform, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
            Text("🔥 ${hotText(danmuMessages)}", style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF7043))
        }

        // 画质 / 线路
        Column(Modifier.padding(horizontal = 12.dp)) {
            LazyRow {
                items(info?.qualities?.size ?: 0) { i ->
                    FilterChip(onClick = { qi = i; li = 0; openStream() }, label = { Text(info!!.qualities[i].name) },
                        selected = i == qi, modifier = Modifier.padding(end = 8.dp))
                }
            }
            if (quality != null && quality.lines.size > 1) {
                LazyRow {
                    items(quality.lines.size) { i ->
                        FilterChip(onClick = { li = i; openStream() }, label = { Text(quality.lines[i].name) },
                            selected = i == li, modifier = Modifier.padding(end = 8.dp))
                    }
                }
            }
        }

        Spacer(Modifier.height(8.dp))
        TabRow(selectedTabIndex = tab) {
            listOf("聊天", "排行", "关注", "设置").forEachIndexed { i, t ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) })
            }
        }

        // 内容区（占满剩余高度）
        when (tab) {
            0 -> LazyColumn(
                Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp)
            ) {
                items(danmuMessages) { m ->
                    val text = if (danmuCfg.showUser && m.userName.isNotEmpty()) "${m.userName}: ${m.message}" else m.message
                    Text(text, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp),
                        color = MaterialTheme.colorScheme.onBackground)
                }
            }
            2 -> Column(Modifier.fillMaxWidth().weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center) {
                Text("关注列表请到「直播」页管理", color = Color.Gray)
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    scope.launch {
                        Api.call("live_follow_add", mapOf("platform" to platform, "roomId" to roomId, "title" to title, "userName" to userName, "cover" to ""))
                        followed = true
                    }
                }) { Text(if (followed) "已关注" else "关注主播") }
            }
            else -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { Text("暂无内容", color = Color.Gray) }
        }

        // 底部操作栏
        Row(
            Modifier.fillMaxWidth().height(56.dp).background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            TextButtonIcon(if (followed) "已关注" else "关注", Icons.Filled.Favorite,
                if (followed) Color(0xFFE91E63) else MaterialTheme.colorScheme.onSurface) {
                scope.launch {
                    Api.call("live_follow_add", mapOf("platform" to platform, "roomId" to roomId, "title" to title, "userName" to userName, "cover" to ""))
                    followed = !followed
                }
            }
            TextButtonIcon("刷新", Icons.Filled.Refresh, MaterialTheme.colorScheme.onSurface) {
                scope.launch {
                    val pr = Api.call("live_danmaku_poll", mapOf("platform" to platform, "room" to roomId))
                    val msgs = pr.optJSONArray("messages")?.let { arr ->
                        (0 until arr.length()).map { LiveDanmuMessage.from(arr.getJSONObject(it)) }
                    } ?: emptyList()
                    danmuMessages = msgs.takeLast(100)
                }
            }
            TextButtonIcon("分享", Icons.Filled.Share, MaterialTheme.colorScheme.onSurface) {}
        }
    }

    if (fullscreen) {
        FullscreenVideoDialog(
            controller = controller,
            title = title.ifEmpty { userName },
            onDismiss = { fullscreen = false }
        )
    }
}

@Composable
private fun TextButtonIcon(label: String, icon: ImageVector, color: Color, onClick: () -> Unit) {
    Row(modifier = Modifier.clickable(onClick = onClick).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, label, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(4.dp))
        Text(label, color = color, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun hotText(messages: List<LiveDanmuMessage>): String {
    val online = messages.lastOrNull()?.online ?: 0
    return if (online > 0) "$online" else "--"
}
