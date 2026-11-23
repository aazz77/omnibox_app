package com.omnibox.app.ui.live

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.omnibox.app.core.Api
import com.omnibox.app.core.ObImage
import com.omnibox.app.models.LiveFollow
import com.omnibox.app.models.LivePlayInfo
import com.omnibox.app.models.LiveSearchItem
import com.omnibox.app.models.LiveSite
import com.omnibox.app.models.str
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private sealed class LiveRoute { object Follow : LiveRoute(); object Search : LiveRoute(); data class Player(val platform: String, val roomId: String, val title: String, val userName: String) : LiveRoute() }

@Composable
fun LiveScreen() {
    var route by remember { mutableStateOf<LiveRoute>(LiveRoute.Follow) }
    var initialKw by remember { mutableStateOf("") }
    when (val r = route) {
        LiveRoute.Follow -> FollowPage(
            onSearch = { initialKw = it; route = LiveRoute.Search },
            onPlay = { p, room, t, u -> route = LiveRoute.Player(p, room, t, u) }
        )
        LiveRoute.Search -> SearchPage(
            initialKw = initialKw,
            onBack = { route = LiveRoute.Follow },
            onPlay = { p, room, t, u -> route = LiveRoute.Player(p, room, t, u) }
        )
        is LiveRoute.Player -> LivePlayerPage(r.platform, r.roomId, r.title, r.userName, onBack = { route = LiveRoute.Follow })
    }
}

@Composable
private fun FollowPage(onSearch: (String) -> Unit, onPlay: (String, String, String, String) -> Unit) {
    var sites by remember { mutableStateOf<List<LiveSite>>(emptyList()) }
    var follows by remember { mutableStateOf<List<LiveFollow>>(emptyList()) }
    var platform by remember { mutableStateOf("all") }
    var loading by remember { mutableStateOf(true) }
    var addDialog by remember { mutableStateOf(false) }
    var importDialog by remember { mutableStateOf(false) }
    var exportDialog by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun load() = scope.launch {
        loading = true
        val rs = Api.call("live_sites")
        sites = rs.optJSONArray("sites")?.let { arr -> (0 until arr.length()).map { LiveSite.from(arr.getJSONObject(it)) } } ?: emptyList()
        val rf = Api.call("live_follows")
        follows = rf.optJSONArray("items")?.let { arr -> (0 until arr.length()).map { LiveFollow.from(arr.getJSONObject(it)) } } ?: emptyList()
        loading = false
    }
    LaunchedEffect(Unit) { load() }

    val shown = follows.filter { platform == "all" || it.platform == platform }.sortedByDescending { it.top }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        OutlinedTextField(value = "", onValueChange = {}, readOnly = true, placeholder = { Text("搜索直播间 / 主播，或粘贴分享链接") },
            modifier = Modifier.fillMaxWidth().clickable { onSearch("") }, singleLine = true)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.foundation.lazy.LazyRow(Modifier.weight(1f)) {
                item { FilterChip(onClick = { platform = "all" }, label = { Text("全部") }, selected = platform == "all") }
                items(sites) { s -> FilterChip(onClick = { platform = s.id }, label = { Text(s.name) }, selected = platform == s.id) }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("直播中 ${follows.count { it.live }} / 全部 ${follows.size}", style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.weight(1f))
            Button(onClick = { exportDialog = "加载中..." ; scope.launch {
                val r = Api.call("live_follows_export")
                exportDialog = r.toString(2)
            } }) { Text("导出") }
            Spacer(Modifier.width(4.dp))
            Button(onClick = { importDialog = true }) { Text("导入") }
            Spacer(Modifier.width(4.dp))
            Button(onClick = { addDialog = true }) { Text("添加") }
        }
        Spacer(Modifier.height(8.dp))
        if (loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else if (shown.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Button(onClick = { onSearch("") }) { Text("去搜索发现主播") } }
        else LazyVerticalGrid(columns = GridCells.Adaptive(200.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(shown) { f ->
                Card(modifier = Modifier.clickable { onPlay(f.platform, f.roomId, f.title, f.userName) }) {
                    Column {
                        Box(Modifier.fillMaxWidth().height(110.dp)) {
                            ObImage(f.cover, Modifier.fillMaxSize())
                            if (f.live) Text("直播中", color = Color.White, modifier = Modifier.padding(6.dp).background(Color.Red))
                            Text(f.platform, color = Color.White, modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Color(0x99000000)))
                        }
                        Column(Modifier.padding(8.dp)) {
                            Text(f.title.ifEmpty { f.roomId }, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(f.userName, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                            Row {
                                Text(if (f.top) "取消置顶" else "置顶", modifier = Modifier.clickable {
                                    scope.launch { Api.call("live_follow_top", mapOf("id" to f.id, "top" to !f.top)); load() }
                                }, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
                                Spacer(Modifier.width(12.dp))
                                Text("删除", modifier = Modifier.clickable {
                                    scope.launch { Api.call("live_follow_del", mapOf("id" to f.id)); load() }
                                }, color = Color.Red, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
    }
    if (addDialog) AddFollowDialog(sites, onDismiss = { addDialog = false }, onDone = { addDialog = false; load() })
    if (importDialog) ImportFollowDialog(onDismiss = { importDialog = false }, onDone = { importDialog = false; load() })
    exportDialog?.let { TextExportDialog(it) { exportDialog = null } }
}

@Composable
private fun AddFollowDialog(sites: List<LiveSite>, onDismiss: () -> Unit, onDone: () -> Unit) {
    var platform by remember { mutableStateOf(sites.firstOrNull()?.id ?: "bilibili") }
    var input by remember { mutableStateOf("") }
    var expanded by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    androidx.compose.material3.AlertDialog(onDismissRequest = onDismiss, title = { Text("添加关注") },
        text = {
            Column {
                Box { Button(onClick = { expanded = true }) { Text("平台: ${sites.firstOrNull { it.id == platform }?.name ?: platform}") }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        sites.forEach { DropdownMenuItem(text = { Text(it.name) }, onClick = { platform = it.id; expanded = false }) }
                    }
                }
                OutlinedTextField(value = input, onValueChange = { input = it }, label = { Text("房间号 / 分享链接") }, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            Button(onClick = {
                scope.launch {
                    var p = platform; var room = input
                    runCatching {
                        val r = Api.call("live_parse", mapOf("text" to input))
                        if (r.optBoolean("ok")) { p = r.str("platform"); room = r.str("roomId") }
                    }
                    if (room.isNotEmpty()) { Api.call("live_follow_add", mapOf("platform" to p, "roomId" to room, "title" to "", "cover" to "", "userName" to "")); onDone() }
                }
            }) { Text("添加") }
        }, dismissButton = { Button(onClick = onDismiss) { Text("取消") } })
}

@Composable
private fun ImportFollowDialog(onDismiss: () -> Unit, onDone: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    androidx.compose.material3.AlertDialog(onDismissRequest = onDismiss, title = { Text("导入关注列表") },
        text = {
            Column {
                OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("JSON（数组 / {follows:[...]}）") },
                    modifier = Modifier.fillMaxWidth().height(160.dp), maxLines = 8)
                msg?.let { Text(it) }
            }
        },
        confirmButton = {
            Button(onClick = {
                scope.launch {
                    runCatching {
                        val arr = JSONArray(text)
                        val r = Api.call("live_follows_import", mapOf("data" to arr))
                        msg = "新增 ${r.optInt("imported")} 条"
                        if (r.optBoolean("ok")) { delay(300); onDone() }
                    }.onFailure { msg = "导入失败: ${it.message}" }
                }
            }) { Text("导入") }
        }, dismissButton = { Button(onClick = onDismiss) { Text("取消") } })
}

@Composable
private fun TextExportDialog(text: String, onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(onDismissRequest = onDismiss, title = { Text("导出关注") },
        text = { androidx.compose.foundation.text.selection.SelectionContainer { Text(text, style = MaterialTheme.typography.bodySmall) } },
        confirmButton = { Button(onClick = onDismiss) { Text("关闭") } })
}

@Composable
private fun SearchPage(initialKw: String, onBack: () -> Unit, onPlay: (String, String, String, String) -> Unit) {
    var sites by remember { mutableStateOf<List<LiveSite>>(emptyList()) }
    var platform by remember { mutableStateOf("bilibili") }
    var keyword by remember { mutableStateOf(initialKw) }
    var items by remember { mutableStateOf<List<LiveSearchItem>>(emptyList()) }
    var page by remember { mutableStateOf(1) }
    var hasMore by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(false) }
    var anchor by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    suspend fun doSearch(p: Int) {
        loading = true
        val r = Api.call("live_search", mapOf("platform" to platform, "kw" to keyword, "page" to p, "anchor" to anchor))
        items = r.optJSONArray("items")?.let { arr -> (0 until arr.length()).map { LiveSearchItem.from(arr.getJSONObject(it)) } } ?: emptyList()
        hasMore = r.optBoolean("hasMore"); page = p; loading = false
    }

    LaunchedEffect(Unit) {
        val r = Api.call("live_sites")
        sites = r.optJSONArray("sites")?.let { arr -> (0 until arr.length()).map { LiveSite.from(arr.getJSONObject(it)) } } ?: emptyList()
        platform = sites.firstOrNull { it.searchable }?.id ?: "bilibili"
        if (keyword.isNotEmpty()) doSearch(1)
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "返回") }
            Box {
                Button(onClick = { expanded = true }) { Text(sites.firstOrNull { it.id == platform }?.name ?: platform) }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    sites.filter { it.searchable }.forEach { DropdownMenuItem(text = { Text(it.name) }, onClick = { platform = it.id; expanded = false }) }
                }
            }
            Spacer(Modifier.width(4.dp))
            OutlinedTextField(value = keyword, onValueChange = { keyword = it }, label = { Text("关键词") }, modifier = Modifier.weight(1f), singleLine = true)
            Button(onClick = { scope.launch { doSearch(1) } }) { Text("搜索") }
        }
        FilterChip(onClick = { anchor = !anchor }, label = { Text(if (anchor) "主播" else "直播间") }, selected = anchor)
        if (loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else LazyColumn(Modifier.fillMaxSize()) {
            items(items) { it2 ->
                Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    ObImage(it2.cover, Modifier.width(84.dp).height(52.dp))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(it2.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(it2.userName + if (it2.liveStatus) " [直播中]" else "", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                    }
                    Button(onClick = { scope.launch { Api.call("live_follow_add", mapOf("platform" to platform, "roomId" to it2.roomId, "title" to it2.title, "cover" to it2.cover, "userName" to it2.userName)) } }) { Text("关注") }
                    Spacer(Modifier.width(4.dp))
                    Button(onClick = { onPlay(platform, it2.roomId, it2.title, it2.userName) }) { Text("播放") }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    Button(onClick = { scope.launch { doSearch(page - 1) } }, enabled = page > 1) { Text("上一页") }
                    Text("第 $page 页", modifier = Modifier.padding(12.dp))
                    Button(onClick = { scope.launch { doSearch(page + 1) } }, enabled = hasMore) { Text("下一页") }
                }
            }
        }
    }
}
