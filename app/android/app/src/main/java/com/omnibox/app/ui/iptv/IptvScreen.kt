package com.omnibox.app.ui.iptv

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.AppSettings
import com.omnibox.app.core.IptvStore
import com.omnibox.app.core.M3uParser
import com.omnibox.app.models.IptvSource
import kotlinx.coroutines.launch

@Composable
fun IptvScreen() {
    var version by remember { mutableStateOf(0) }
    var editor by remember { mutableStateOf<Int?>(null) }
    var player by remember { mutableStateOf<Pair<Int, String>?>(null) } // index,-1=builtin
    val showBuiltin by AppSettings.showBuiltinIptv.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    when (val p = player) {
        null -> {
            Column(Modifier.fillMaxSize().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("IPTV", style = MaterialTheme.typography.headlineSmall)
                    Spacer(Modifier.weight(1f))
                    Button(onClick = { editor = -1 }) { Icon(Icons.Filled.Add, null); Text("导入") }
                }
                val sources = IptvStore.sources
                if (sources.isEmpty() && !showBuiltin) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("暂无 IPTV 源，点击右上角导入") }
                } else {
                    LazyVerticalGrid(columns = GridCells.Adaptive(240.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (showBuiltin) {
                            item {
                                Card(Modifier.fillMaxWidth().clickable { player = -1 to "央视频（内置）" }) {
                                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Filled.WifiTethering, null, modifier = Modifier.size(36.dp), tint = Color(0xFF3F51B5))
                                        Spacer(Modifier.width(8.dp))
                                        Column { Text("央视频", style = MaterialTheme.typography.titleSmall); Text("内置 · 央视/卫视 64 路", style = MaterialTheme.typography.bodySmall, color = Color.Gray) }
                                    }
                                }
                            }
                        }
                        itemsIndexed(sources) { i, s ->
                            Card(Modifier.fillMaxWidth().clickable { player = i to s.name }) {
                                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.WifiTethering, null, modifier = Modifier.size(36.dp))
                                    Spacer(Modifier.width(8.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(s.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                                        Text(if (s.isNetwork) "远程${if (s.autoUpdate) " · 自动更新" else ""}" else "文件", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                                    }
                                    IconButton(onClick = { scope.launch { IptvStore.loadContent(i) } }) { Icon(Icons.Filled.Refresh, null) }
                                    IconButton(onClick = { editor = i }) { Icon(Icons.Filled.Edit, null) }
                                    IconButton(onClick = { IptvStore.remove(i); version++ }) { Icon(Icons.Filled.Delete, null, tint = Color.Red) }
                                }
                            }
                        }
                    }
                }
            }
        }
        else -> IptvPlayerPage(sourceIndex = p.first, sourceName = p.second, onBack = { player = null })
    }

    editor?.let { idx ->
        IptvEditorDialog(index = idx, onDismiss = { editor = null }, onSave = { s ->
            if (idx < 0) IptvStore.add(s) else IptvStore.update(idx, s)
            editor = null; version++
        })
    }
}

@Composable
private fun IptvEditorDialog(index: Int, onDismiss: () -> Unit, onSave: (IptvSource) -> Unit) {
    val existing = if (index >= 0) IptvStore.sources.getOrNull(index) else null
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var type by remember { mutableStateOf(existing?.type ?: "network") }
    var url by remember { mutableStateOf(existing?.url ?: "") }
    var path by remember { mutableStateOf(existing?.filePath ?: "") }
    var auto by remember { mutableStateOf(existing?.autoUpdate ?: false) }
    var err by remember { mutableStateOf<String?>(null) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(if (index < 0) "导入 IPTV 源" else "编辑 IPTV 源") },
        text = {
            Column {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称 *") }, modifier = Modifier.fillMaxWidth(), isError = name.isBlank())
                Row { Button(onClick = { type = "network" }) { Text("远程") }; Spacer(Modifier.width(4.dp)); Button(onClick = { type = "file" }) { Text("文件") } }
                if (type == "network") {
                    OutlinedTextField(value = url, onValueChange = { url = it }, label = { Text("M3U 链接") }, modifier = Modifier.fillMaxWidth())
                    Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(checked = auto, onCheckedChange = { auto = it }); Text("启动时自动更新") }
                } else {
                    OutlinedTextField(value = path, onValueChange = { path = it }, label = { Text("本地文件路径") }, modifier = Modifier.fillMaxWidth())
                }
                err?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            Button(onClick = {
                if (name.isBlank()) { err = "名称不能为空"; return@Button }
                if (type == "network" && url.isBlank()) { err = "请输入 M3U 链接"; return@Button }
                if (type == "file" && path.isBlank()) { err = "请选择本地文件"; return@Button }
                onSave(IptvSource(name, type, url, path, "", auto))
            }) { Text("保存") }
        }, dismissButton = { Button(onClick = onDismiss) { Text("取消") } })
}
