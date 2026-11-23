package com.omnibox.app.ui.iptv

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.omnibox.app.core.Api
import com.omnibox.app.core.IptvStore
import com.omnibox.app.core.M3uParser
import com.omnibox.app.models.M3uChannel
import com.omnibox.app.models.str
import com.omnibox.app.player.FullscreenVideoDialog
import com.omnibox.app.player.MediaPlayerController
import com.omnibox.app.player.VideoView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun IptvPlayerPage(sourceIndex: Int, sourceName: String, onBack: () -> Unit) {
    var channels by remember { mutableStateOf<List<M3uChannel>>(emptyList()) }
    var grouped by remember { mutableStateOf<LinkedHashMap<String, List<M3uChannel>>>(linkedMapOf()) }
    var browseGroup by remember { mutableStateOf("") }
    var currentName by remember { mutableStateOf("") }
    var streamUrls by remember { mutableStateOf<List<String>>(emptyList()) }
    var streamIndex by remember { mutableStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var fullscreen by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(true) }

    val appContext = androidx.compose.ui.platform.LocalContext.current
    val controller = remember { MediaPlayerController(appContext) }

    fun selectChannel(ch: M3uChannel) {
        val urls = channels.filter { it.name == ch.name }.map { it.url }.distinct()
        streamUrls = urls.ifEmpty { listOf(ch.url) }
        streamIndex = 0
        currentName = ch.name
        controller.open(streamUrls.first())
    }

    LaunchedEffect(sourceIndex) {
        loading = true
        runCatching {
            val list = if (sourceIndex == -1) loadBuiltinChannels() else IptvStore.loadChannels(sourceIndex)
            channels = list
            val g = M3uParser.groupBy(list)
            grouped = g
            browseGroup = g.keys.firstOrNull().orEmpty()
            g.values.firstOrNull()?.firstOrNull()?.let { selectChannel(it) }
        }.onFailure { error = it.message }
        loading = false
    }
    DisposableEffect(Unit) { onDispose { controller.release() } }

    Column(Modifier.fillMaxSize().background(Color.Black)) {
        // 视频区（16:9）
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            if (!fullscreen && streamUrls.isNotEmpty()) VideoView(controller, Modifier.fillMaxSize())
            Row(
                Modifier.fillMaxWidth().background(Color(0x99000000)).padding(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回", tint = Color.White) }
                Text(currentName.ifEmpty { sourceName }, color = Color.White, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text("LIVE", color = Color.Red)
                IconButton(onClick = { if (streamUrls.isNotEmpty()) fullscreen = true }) {
                    Icon(Icons.Filled.Fullscreen, "全屏", tint = Color.White)
                }
            }
            if (loading) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
            error?.let { Text(it, color = Color.White, modifier = Modifier.align(Alignment.Center).padding(16.dp)) }
        }

        // 标题 + 设置
        Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(currentName.ifEmpty { "IPTV" }, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            IconButton(onClick = { showSettings = !showSettings }) {
                Icon(Icons.Filled.Settings, "设置")
            }
        }

        if (showSettings) {
            // 线路
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                streamUrls.forEachIndexed { i, _ ->
                    FilterChip(
                        onClick = { streamIndex = i; controller.open(streamUrls[i]) },
                        label = { Text("源 ${i + 1}") },
                        selected = i == streamIndex,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                }
            }

            // 三栏频道面板：分组 / 频道
            Row(Modifier.fillMaxSize().padding(8.dp)) {
                // 分组
                LazyColumn(Modifier.weight(0.35f).fillMaxSize()) {
                    items(grouped.keys.toList()) { g ->
                        Text(
                            g,
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (g == browseGroup) MaterialTheme.colorScheme.primary else Color.Gray,
                            modifier = Modifier.fillMaxWidth().clickable { browseGroup = g }.padding(10.dp),
                            maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                Spacer(Modifier.width(8.dp))
                // 频道
                LazyColumn(Modifier.weight(0.65f).fillMaxSize()) {
                    val list = grouped[browseGroup].orEmpty().distinctBy { it.name }
                    items(list) { ch ->
                        Text(
                            ch.name,
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (ch.name == currentName) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.fillMaxWidth().clickable { selectChannel(ch) }.padding(10.dp),
                            maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }

    if (fullscreen) {
        FullscreenVideoDialog(
            controller = controller,
            title = currentName.ifEmpty { sourceName },
            onDismiss = { fullscreen = false }
        )
    }
}

private suspend fun loadBuiltinChannels(): List<M3uChannel> = withContext(Dispatchers.IO) {
    val portR = Api.call("iptv_yspl_port")
    if (!portR.optBoolean("ok")) throw Exception(portR.optString("error", "内置服务端口无效"))
    val port = portR.optInt("port")
    val chR = Api.call("iptv_yspl_channels")
    if (!chR.optBoolean("ok")) throw Exception(chR.optString("error", "频道表获取失败"))
    val arr = chR.optJSONArray("channels") ?: throw Exception("内置央视频频道表为空")
    val out = (0 until arr.length()).mapNotNull { i ->
        val j = arr.getJSONObject(i)
        val slug = j.str("slug")
        if (slug.isEmpty()) null else M3uChannel(
            name = j.str("name", slug),
            url = "http://127.0.0.1:$port/$slug.m3u8",
            group = j.str("group", "央视频"),
            logo = j.str("logo"),
            id = j.str("tvgId")
        )
    }
    if (out.isEmpty()) throw Exception("内置央视频频道表为空")
    out
}
