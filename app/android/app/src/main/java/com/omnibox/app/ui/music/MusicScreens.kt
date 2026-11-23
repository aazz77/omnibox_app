package com.omnibox.app.ui.music

import android.annotation.SuppressLint
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicVideo
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.core.ObImage
import com.omnibox.app.models.MusicBoard
import com.omnibox.app.models.MusicSong
import com.omnibox.app.models.str
import kotlinx.coroutines.launch

private data class Platform(val key: String, val label: String)
private val PLATFORMS = listOf(Platform("kw", "酷我"), Platform("kg", "酷狗"), Platform("tx", "QQ"), Platform("wy", "网易云"), Platform("mg", "咪咕"))

private sealed class MusicRoute { object Home : MusicRoute(); data class List(val board: MusicBoard?) : MusicRoute(); object Player : MusicRoute(); data class Mv(val song: MusicSong) : MusicRoute() }

@Composable
fun MusicScreen() {
    var route by remember { mutableStateOf<MusicRoute>(MusicRoute.Home) }
    var listQuery by remember { mutableStateOf("") }

    when (val r = route) {
        MusicRoute.Home -> MusicHome(
            onBoard = { route = MusicRoute.List(it) },
            onSearch = { listQuery = it; route = MusicRoute.List(null) }
        )
        is MusicRoute.List -> MusicList(
            board = r.board, initialQuery = listQuery,
            onBack = { route = MusicRoute.Home },
            onPlay = { route = MusicRoute.Player },
            onMv = { route = MusicRoute.Mv(it) }
        )
        MusicRoute.Player -> MusicPlayerPage(
            onBack = { route = MusicRoute.Home },
            onMv = { route = MusicRoute.Mv(it) }
        )
        is MusicRoute.Mv -> MvPage(song = r.song, onBack = { route = MusicRoute.Player })
    }

    // 迷你播放条（除 MV 页外常驻）
    if (route !is MusicRoute.Mv) MiniBar(onOpen = { route = MusicRoute.Player })
}

@Composable
private fun MusicHome(onBoard: (MusicBoard) -> Unit, onSearch: (String) -> Unit) {
    var platform by remember { mutableStateOf("kw") }
    var boards by remember { mutableStateOf<List<MusicBoard>>(emptyList()) }
    var hot by remember { mutableStateOf<List<String>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var query by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    fun load() = scope.launch {
        loading = true
        val rb = Api.call("music_boards", mapOf("source" to platform))
        boards = rb.optJSONArray("list")?.let { arr -> (0 until arr.length()).map { MusicBoard.from(arr.getJSONObject(it)) } } ?: emptyList()
        val rh = Api.call("music_hot_search", mapOf("source" to platform))
        hot = (rh.optJSONArray("list") ?: rh.optJSONArray("data"))?.let { arr ->
            (0 until arr.length()).mapNotNull { i ->
                val v = arr.opt(i)
                when (v) { is String -> v; is org.json.JSONObject -> v.str("name", v.str("keyword")); else -> null }
            }.filter { it.isNotEmpty() }
        } ?: emptyList()
        loading = false
    }
    LaunchedEffect(platform) { load() }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row {
            OutlinedTextField(value = query, onValueChange = { query = it }, placeholder = { Text("搜索歌曲、歌手、专辑") },
                modifier = Modifier.weight(1f), singleLine = true)
            Spacer(Modifier.width(8.dp))
            Button(onClick = { if (query.isNotBlank()) onSearch(query.trim()) }) { Text("搜索") }
        }
        if (hot.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth()) {
                Text("热搜:", style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.width(4.dp))
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    hot.take(10).forEach { h -> FilterChip(selected = false, onClick = { query = h; onSearch(h) }, label = { Text(h, style = MaterialTheme.typography.bodySmall) }) }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("排行榜", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(6.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            PLATFORMS.forEachIndexed { i, p ->
                SegmentedButton(selected = platform == p.key, onClick = { platform = p.key }, shape = androidx.compose.ui.graphics.RectangleShape) {
                    Text(p.label)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        if (loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else LazyVerticalGrid(columns = GridCells.Adaptive(160.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(boards) { b ->
                Card(modifier = Modifier.clickable { onBoard(b) }) {
                    Column(Modifier.padding(12.dp)) {
                        Text("🏆  ${b.bangid}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                        Spacer(Modifier.height(8.dp))
                        Text(b.name, maxLines = 2, style = MaterialTheme.typography.titleSmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun MusicList(board: MusicBoard?, initialQuery: String, onBack: () -> Unit, onPlay: () -> Unit, onMv: (MusicSong) -> Unit) {
    var songs by remember { mutableStateOf<List<MusicSong>>(emptyList()) }
    var page by remember { mutableStateOf(1) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    val title = board?.name ?: "搜索: $initialQuery"

    fun load(p: Int) = scope.launch {
        loading = true
        val r = if (board != null) Api.call("music_board_list", mapOf("source" to board.source, "bangid" to board.bangid, "page" to p))
                else Api.call("music_search", mapOf("source" to "kw", "keyword" to initialQuery, "page" to p, "limit" to 30))
        val list = r.optJSONArray("list")?.let { arr -> (0 until arr.length()).map { MusicSong.from(arr.getJSONObject(it)) } } ?: emptyList()
        songs = if (p == 1) list else songs + list
        page = p; hasMore = list.isNotEmpty(); loading = false
    }
    LaunchedEffect(Unit) { load(1) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回") }
            Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (loading && songs.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else LazyColumn(Modifier.fillMaxSize()) {
            itemsIndexed(songs) { i, song ->
                ListItem(song = song, index = i,
                    onClick = {
                        MusicPlayerRepository.playSongs(songs, i)
                        startMusicService(song.name, song.singer)
                        onPlay()
                    },
                    onMv = if (song.mvSupported) { { onMv(song) } } else null)
            }
            if (hasMore && !loading) item { Button(onClick = { load(page + 1) }, modifier = Modifier.fillMaxWidth().padding(8.dp)) { Text("加载更多") } }
        }
    }
}

@Composable
private fun ListItem(song: MusicSong, index: Int, onClick: () -> Unit, onMv: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (song.picUrl.startsWith("http")) ObImage(song.picUrl, Modifier.width(44.dp).height(44.dp))
        else Box(Modifier.width(44.dp).height(44.dp).background(Color(0xFFE8E8F0)), contentAlignment = Alignment.Center) { Text("${index + 1}") }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(song.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOf(song.singer, song.albumName, song.interval).filter { it.isNotEmpty() }.joinToString(" · "),
                style = MaterialTheme.typography.bodySmall, color = Color.Gray, maxLines = 1)
        }
        if (onMv != null) IconButton(onClick = onMv) { Icon(Icons.Filled.MusicVideo, "MV", tint = Color(0xFF7B1FA2)) }
    }
}

@SuppressLint("UnusedMaterial3ScaffoldPaddingParameter")
@Composable
private fun MusicPlayerPage(onBack: () -> Unit, onMv: (MusicSong) -> Unit) {
    val song by MusicPlayerRepository.currentSongFlow.collectAsStateWithLifecycle()
    val playing by MusicPlayerRepository.playing.collectAsStateWithLifecycle()
    val position by MusicPlayerRepository.position.collectAsStateWithLifecycle()
    val duration by MusicPlayerRepository.duration.collectAsStateWithLifecycle()
    val lrcLines by MusicPlayerRepository.lrcLines.collectAsStateWithLifecycle()
    val lrcIndex by MusicPlayerRepository.lrcIndex.collectAsStateWithLifecycle()
    val quality by MusicPlayerRepository.quality.collectAsStateWithLifecycle()
    val prefQuality by AppSettings.preferredQuality.collectAsStateWithLifecycle()
    val index by MusicPlayerRepository.index.collectAsStateWithLifecycle()
    val error by MusicPlayerRepository.error.collectAsStateWithLifecycle()
    var showQueue by remember { mutableStateOf(false) }
    var qualityExpanded by remember { mutableStateOf(false) }

    val pagerState = androidx.compose.foundation.pager.rememberPagerState(pageCount = { 2 })
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    val scope = rememberCoroutineScope()

    // 歌词自动滚动到当前行
    LaunchedEffect(lrcIndex, lrcLines.size) {
        if (lrcIndex >= 0 && lrcIndex < lrcLines.size) {
            runCatching { listState.animateScrollToItem(lrcIndex.coerceAtLeast(0)) }
        }
    }

    Column(Modifier.fillMaxSize().background(Color(0xFFF7F5FA))) {
        // 顶部标题栏：歌名 - 歌手
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回") }
            Column(Modifier.weight(1f)) {
                Text(song?.name ?: "未播放", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(song?.singer ?: "", style = MaterialTheme.typography.bodySmall, color = Color.Gray, maxLines = 1)
            }
            if (song?.mvSupported == true) IconButton(onClick = { song?.let { onMv(it) } }) { Icon(Icons.Filled.MusicVideo, "MV") }
            Button(onClick = { qualityExpanded = true }) { Text(AppSettings.qualityLabel(quality), style = MaterialTheme.typography.bodySmall) }
            DropdownMenu(expanded = qualityExpanded, onDismissRequest = { qualityExpanded = false }) {
                AppSettings.musicQualityOptions.forEach { opt ->
                    DropdownMenuItem(text = { Text(opt.label) }, onClick = { MusicPlayerRepository.setQuality(opt.value); qualityExpanded = false })
                }
            }
        }

        // 左右滑动：封面 / 歌词
        androidx.compose.foundation.pager.HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth().weight(1f)
        ) { page ->
            when (page) {
                0 -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    val coverUrl = song?.picUrl
                    if (!coverUrl.isNullOrEmpty() && coverUrl.startsWith("http")) {
                        ObImage(coverUrl, Modifier.width(260.dp).aspectRatio(1f))
                    } else {
                        Box(Modifier.width(260.dp).aspectRatio(1f).background(Color(0xFFE8E8F0)), contentAlignment = Alignment.Center) {
                            Text("🎵", style = MaterialTheme.typography.displayLarge)
                        }
                    }
                }
                1 -> androidx.compose.foundation.lazy.LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    item { Spacer(Modifier.height(120.dp)) }
                    itemsIndexed(lrcLines) { i, line ->
                        Text(
                            line.text,
                            style = if (i == lrcIndex) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge,
                            color = if (i == lrcIndex) MaterialTheme.colorScheme.primary else Color.Gray,
                            modifier = Modifier.padding(vertical = 10.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                    item { Spacer(Modifier.height(120.dp)) }
                }
            }
        }

        // 页码指示
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            repeat(2) { i ->
                Box(
                    Modifier.padding(4.dp).size(8.dp).clip(CircleShape)
                        .background(if (pagerState.currentPage == i) MaterialTheme.colorScheme.primary else Color(0xFFD0C8DE))
                )
            }
        }

        // 进度条
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Slider(
                value = if (duration > 0) position.toFloat() else 0f,
                onValueChange = { MusicPlayerRepository.seek(it.toLong()) },
                valueRange = 0f..duration.coerceAtLeast(1).toFloat()
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(fmt(position), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                Text(fmt(duration), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }

        // 播放控制
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { MusicPlayerRepository.cycleRepeat() }) {
                Text(when (MusicPlayerRepository.repeatMode.value) {
                    com.omnibox.app.ui.music.PlayMode.ONE -> "🔂"; com.omnibox.app.ui.music.PlayMode.SHUFFLE -> "🔀"; else -> "🔁"
                })
            }
            IconButton(onClick = { MusicPlayerRepository.previous() }) { Text("⏮", style = MaterialTheme.typography.headlineMedium) }
            IconButton(onClick = { MusicPlayerRepository.playPause() }) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, "播放/暂停", modifier = Modifier.size(48.dp))
            }
            IconButton(onClick = { MusicPlayerRepository.next() }) { Text("⏭", style = MaterialTheme.typography.headlineMedium) }
            IconButton(onClick = { showQueue = !showQueue }) { Icon(Icons.Filled.QueueMusic, "队列") }
        }

        // 降级提示 / 错误
        val pi = AppSettings.musicQualityPriority.indexOf(prefQuality)
        val qi = AppSettings.musicQualityPriority.indexOf(quality)
        if (pi >= 0 && qi > pi) Text("偏好「${AppSettings.qualityLabel(prefQuality)}」不可用，已降级为「${AppSettings.qualityLabel(quality)}」",
            color = Color.Gray, style = MaterialTheme.typography.bodySmall, modifier = Modifier.align(Alignment.CenterHorizontally))
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.align(Alignment.CenterHorizontally)) }

        if (showQueue) {
            Text("播放队列 (${MusicPlayerRepository.queue.size})", modifier = Modifier.padding(8.dp))
            LazyColumn(Modifier.weight(0.6f)) {
                itemsIndexed(MusicPlayerRepository.queue) { i, t ->
                    Row(Modifier.fillMaxWidth().clickable { MusicPlayerRepository.playAt(i) }.padding(8.dp)) {
                        Text("${i + 1}. ${t.song.name} - ${t.song.singer}", color = if (i == index) MaterialTheme.colorScheme.primary else Color.Unspecified)
                    }
                }
            }
        }
    }
}

@Composable
private fun MiniBar(onOpen: () -> Unit) {
    val song by MusicPlayerRepository.currentSongFlow.collectAsStateWithLifecycle()
    val playing by MusicPlayerRepository.playing.collectAsStateWithLifecycle()
    song?.let { s ->
        Row(Modifier.fillMaxWidth().height(56.dp).background(Color(0xFFE8E8F0)).clickable(onClick = onOpen).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(s.name, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            IconButton(onClick = { MusicPlayerRepository.playPause() }) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, "播放/暂停")
            }
            IconButton(onClick = { MusicPlayerRepository.next() }) { Icon(Icons.Filled.SkipNext, "下一首") }
        }
    }
}

@Composable
private fun MvPage(song: MusicSong, onBack: () -> Unit) {
    var url by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    val appContext = androidx.compose.ui.platform.LocalContext.current
    val controller = remember { com.omnibox.app.player.MediaPlayerController(appContext) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(song) {
        loading = true
        try {
            val info = Api.call("music_mv_info", mapOf("source" to song.source, "songInfo" to song.toInfo()))
            val mvId = info.optString("mv").takeIf { it.isNotEmpty() && it != "0" }
            if (mvId == null) { error = "这首歌暂无 MV"; loading = false; return@LaunchedEffect }
            val urlR = Api.call("music_mv_url", mapOf("source" to song.source, "mvId" to mvId))
            val u = urlR.optString("url")
            if (urlR.optBoolean("ok") && u.isNotEmpty()) { url = u; controller.open(u) }
            else error = urlR.optString("error", "未找到 MV 播放链接")
            loading = false
        } catch (e: Exception) { error = e.message; loading = false }
    }
    DisposableEffect(Unit) { onDispose { controller.release() } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (loading) CircularProgressIndicator(Modifier.align(Alignment.Center))
        else if (error != null) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(error!!, color = Color.White); Button(onClick = onBack) { Text("返回") }
            }
        } else {
            com.omnibox.app.player.VideoView(controller, Modifier.fillMaxSize())
            Row(Modifier.align(Alignment.TopStart).padding(8.dp)) { IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回", tint = Color.White) } }
        }
    }
}

private fun fmt(ms: Long): String { val s = ms / 1000; return "%02d:%02d".format(s / 60, s % 60) }
