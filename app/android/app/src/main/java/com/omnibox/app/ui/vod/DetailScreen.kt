package com.omnibox.app.ui.vod

import android.annotation.SuppressLint
import android.widget.Toast
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.AppSettings
import com.omnibox.app.models.DanmuItem
import com.omnibox.app.models.DanmuSearchItem
import com.omnibox.app.models.Episode
import com.omnibox.app.models.PlayResult
import com.omnibox.app.models.Vod
import com.omnibox.app.player.FullscreenVideoDialog
import com.omnibox.app.player.MediaPlayerController
import com.omnibox.app.player.VideoView
import kotlinx.coroutines.launch

@SuppressLint("UnusedMaterial3ScaffoldPaddingParameter")
@Composable
fun DetailContent(vm: VodViewModel, vod: Vod, onBack: () -> Unit) {
    val detail by vm.detail.collectAsStateWithLifecycle()
    val loading by vm.loading.collectAsStateWithLifecycle()
    val danmuCfg by AppSettings.danmu.collectAsStateWithLifecycle()

    var currentEp by remember { mutableStateOf(-1) }
    var playResult by remember { mutableStateOf<PlayResult?>(null) }
    var playError by remember { mutableStateOf<String?>(null) }
    var danmuItems by remember { mutableStateOf<List<DanmuItem>>(emptyList()) }
    var danmuDialog by remember { mutableStateOf(false) }
    var danmuLabel by remember { mutableStateOf("") }
    var fullscreen by remember { mutableStateOf(false) }
    var showIntro by remember { mutableStateOf(false) }
    var favorited by remember { mutableStateOf(false) }

    val context = LocalContext.current
    val controller = remember { MediaPlayerController(context) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(vod) { vm.loadDetail(vod.source, vod.id) }
    DisposableEffect(Unit) { onDispose { controller.release() } }

    suspend fun playEpisode(index: Int, ep: Episode) {
        playError = null
        val result = vm.resolvePlay(vod.source, ep.q)
        if (result != null && result.url.isNotEmpty()) {
            playResult = result
            currentEp = index
            controller.open(result.url, result.headers)
            vm.recordHistory(vod, index, ep.name)
        } else {
            playError = "播放地址解析失败"
        }
    }

    Column(Modifier.fillMaxSize()) {
        // 顶部标题栏
        Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回") }
            Text(detail?.vod?.name ?: vod.name, style = MaterialTheme.typography.titleMedium,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            IconButton(onClick = { danmuDialog = true }) { Icon(Icons.Filled.Subtitles, "弹幕搜索") }
        }

        if (loading && detail == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (detail == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("详情加载失败: ${vm.error.value}") }
        } else {
            val d = detail!!
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                // 视频区（16:9）
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                    if (!fullscreen && playResult != null) {
                        VideoView(controller, Modifier.fillMaxSize(), danmuItems, danmuCfg.open, danmuCfg)
                    } else if (playResult == null) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("请选择剧集播放", color = Color.Gray)
                                if (playError != null) Text(playError!!, color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                    // 右下角全屏按钮
                    IconButton(
                        onClick = { if (playResult != null) fullscreen = true else Toast.makeText(context, "请先选择剧集", Toast.LENGTH_SHORT).show() },
                        modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp)
                    ) { Icon(Icons.Filled.Fullscreen, "全屏", tint = Color.White) }
                }

                Column(Modifier.padding(horizontal = 16.dp)) {
                    Spacer(Modifier.height(12.dp))
                    // 标题 + 元信息
                    Text(d.vod.name, style = MaterialTheme.typography.headlineSmall)
                    Spacer(Modifier.height(6.dp))
                    val meta = buildList {
                        if (d.year.isNotEmpty()) add("年份: ${d.year}")
                        if (d.area.isNotEmpty()) add("地区: ${d.area}")
                        if (d.type.isNotEmpty()) add("类型: ${d.type}")
                    }.joinToString("  ")
                    Text("来源: ${d.source}${if (meta.isNotEmpty()) "  |  $meta" else ""}",
                        style = MaterialTheme.typography.bodyMedium, color = Color.Gray)
                    if (d.actor.isNotEmpty()) Text("演员: ${d.actor}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                    if (d.director.isNotEmpty()) Text("导演: ${d.director}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                    if (d.remarks.isNotEmpty()) Text(d.remarks, style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF9800))

                    Spacer(Modifier.height(12.dp))
                    // 彩色操作按钮行
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ActionButton("搜索", Color(0xFF2196F3), Modifier.weight(1f)) { danmuDialog = true }
                        ActionButton("简介", Color(0xFF8BC34A), Modifier.weight(1f)) { showIntro = !showIntro }
                        ActionButton(if (favorited) "已收藏" else "加入收藏", Color(0xFFE91E63), Modifier.weight(1f)) {
                            favorited = !favorited
                            Toast.makeText(context, if (favorited) "已加入收藏" else "已取消收藏", Toast.LENGTH_SHORT).show()
                        }
                        ActionButton("下载", Color(0xFF009688), Modifier.weight(1f)) {
                            Toast.makeText(context, "Android 端暂未开放下载", Toast.LENGTH_SHORT).show()
                        }
                    }
                    if (showIntro) {
                        Spacer(Modifier.height(8.dp))
                        Text(d.desc.ifEmpty { "暂无简介" }, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                    }

                    Spacer(Modifier.height(16.dp))
                    // 选集宫格
                    Text("选集", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                }
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(64.dp),
                    modifier = Modifier.fillMaxWidth().height(360.dp).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    itemsIndexed(d.episodes) { i, ep ->
                        Card(
                            modifier = Modifier.clickable { scope.launch { playEpisode(i, ep) } },
                            shape = RoundedCornerShape(6.dp),
                            colors = androidx.compose.material3.CardDefaults.cardColors(
                                containerColor = if (i == currentEp) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Box(Modifier.fillMaxWidth().aspectRatio(1.4f), contentAlignment = Alignment.Center) {
                                Text(ep.name, style = MaterialTheme.typography.bodyMedium,
                                    color = if (i == currentEp) Color.White else MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    if (fullscreen) {
        FullscreenVideoDialog(
            controller = controller,
            title = detail?.vod?.name ?: vod.name,
            showDanmu = danmuCfg.open,
            danmuItems = danmuItems,
            danmuConfig = danmuCfg,
            onDismiss = { fullscreen = false }
        )
    }

    if (danmuDialog) {
        DanmuSearchDialog(
            initialKeyword = detail?.vod?.name ?: vod.name,
            currentLabel = danmuLabel,
            vm = vm,
            onDismiss = { danmuDialog = false },
            onSelected = { items, label ->
                danmuItems = items.sortedBy { it.time }
                danmuLabel = label
                danmuDialog = false
            },
            onClear = { danmuItems = emptyList(); danmuLabel = "" }
        )
    }
}

@Composable
private fun ActionButton(label: String, color: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = modifier.height(40.dp),
        colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = color),
        shape = RoundedCornerShape(20.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
    ) { Text(label, style = MaterialTheme.typography.bodySmall) }
}

private fun formatMs(ms: Long): String {
    val total = ms / 1000
    return "%02d:%02d".format(total / 60, total % 60)
}

@Composable
private fun DanmuSearchDialog(
    initialKeyword: String,
    currentLabel: String,
    vm: VodViewModel,
    onDismiss: () -> Unit,
    onSelected: (List<DanmuItem>, String) -> Unit,
    onClear: () -> Unit
) {
    var keyword by remember { mutableStateOf(initialKeyword) }
    var results by remember { mutableStateOf<List<DanmuSearchItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var loadingId by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("弹幕搜索") },
        text = {
            Column {
                OutlinedTextField(value = keyword, onValueChange = { keyword = it }, label = { Text("关键词") }, singleLine = true)
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    loading = true
                    scope.launch { results = vm.searchDanmu(keyword); loading = false }
                }) { Text("搜索") }
                if (currentLabel.isNotEmpty()) {
                    Text("当前弹幕: $currentLabel", style = MaterialTheme.typography.bodySmall)
                    Button(onClick = onClear) { Text("清空弹幕") }
                }
                Spacer(Modifier.height(8.dp))
                if (loading) CircularProgressIndicator()
                androidx.compose.foundation.lazy.LazyColumn(Modifier.height(300.dp)) {
                    itemsIndexed(results) { _, item ->
                        ListItem(
                            headlineContent = { Text(item.title) },
                            supportingContent = { Text(item.anime) },
                            trailingContent = {
                                if (loadingId == item.id) CircularProgressIndicator(modifier = Modifier.width(20.dp))
                                else IconButton(onClick = {
                                    loadingId = item.id
                                    scope.launch { onSelected(vm.loadDanmu(item.id), item.title) }
                                }) { Icon(Icons.Filled.ArrowBack, "加载") }
                            }
                        )
                    }
                }
            }
        },
        confirmButton = { Button(onClick = onDismiss) { Text("关闭") } }
    )
}
