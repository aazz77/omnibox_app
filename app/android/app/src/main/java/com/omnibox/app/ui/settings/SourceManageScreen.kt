package com.omnibox.app.ui.settings

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.omnibox.app.core.Api
import com.omnibox.app.models.MusicSource
import com.omnibox.app.models.SpiderMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Composable
fun SourceManageScreen() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        ScrollableTabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("点播源") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("音源") })
        }
        if (tab == 0) VodSourcesPane() else MusicSourcesPane()
    }
}

@Composable
private fun VodSourcesPane() {
    var list by remember { mutableStateOf<List<SpiderMeta>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var importDialog by remember { mutableStateOf(false) }
    var sourceDialog by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun reload() = scope.launch {
        loading = true
        val r = Api.spidersList()
        list = r.optJSONArray("list")?.let { arr ->
            (0 until arr.length()).map { SpiderMeta.from(arr.getJSONObject(it)) }
        } ?: emptyList()
        loading = false
    }
    LaunchedEffect(Unit) { reload() }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("点播源 (${list.size})", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            Button(onClick = { importDialog = true }) { Text("导入") }
        }
        if (loading) CircularProgressIndicator()
        LazyColumn(Modifier.fillMaxSize()) {
            items(list, key = { it.id }) { s ->
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(s.displayName, style = MaterialTheme.typography.titleSmall)
                        Text("id: ${s.id} · 来源: ${s.origin}", style = MaterialTheme.typography.bodySmall)
                        if (s.lastError != null) Text("错误: ${s.lastError}", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        Row {
                            Button(onClick = { scope.launch { Api.spidersToggle(s.id, !s.enabled); reload() } }) {
                                Text(if (s.enabled) "禁用" else "启用")
                            }
                            Spacer(Modifier.padding(4.dp))
                            Button(onClick = { scope.launch { val r = Api.spidersTest(s.id); android.widget.Toast.makeText(
                                com.omnibox.app.App.context, "测试: ${r.opt("result")}", android.widget.Toast.LENGTH_SHORT).show() } }) { Text("测试") }
                            Spacer(Modifier.padding(4.dp))
                            Button(onClick = { scope.launch { val r = Api.spidersSource(s.id); sourceDialog = r.optString("source") } }) { Text("源码") }
                            Spacer(Modifier.padding(4.dp))
                            Button(onClick = { scope.launch { Api.spidersRemove(s.id); reload() } }) { Text("删除") }
                        }
                    }
                }
            }
        }
    }

    if (importDialog) VodImportDialog(onDismiss = { importDialog = false }, onDone = { reload(); importDialog = false })
    sourceDialog?.let { TextDialog("脚本源码", it) { sourceDialog = null } }
}

@Composable
private fun VodImportDialog(onDismiss: () -> Unit, onDone: () -> Unit) {
    ImportSourceDialog(
        title = "导入点播源",
        urlLabel = "脚本 URL",
        onImportRemote = { Api.spidersAddUrl(it) },
        onImportLocal = { name, source -> Api.spidersAdd(name, source) },
        onDismiss = onDismiss,
        onDone = onDone,
    )
}

@Composable
private fun MusicSourcesPane() {
    var list by remember { mutableStateOf<List<MusicSource>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var importDialog by remember { mutableStateOf(false) }
    var sourceDialog by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun reload() = scope.launch {
        loading = true
        val r = Api.call("music_source_list")
        list = r.optJSONArray("list")?.let { arr ->
            (0 until arr.length()).map { MusicSource.from(arr.getJSONObject(it)) }
        } ?: emptyList()
        loading = false
    }
    LaunchedEffect(Unit) { reload() }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("音源 (${list.size})", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            Button(onClick = { importDialog = true }) { Text("导入") }
        }
        if (loading) CircularProgressIndicator()
        LazyColumn(Modifier.fillMaxSize()) {
            items(list, key = { it.id }) { s ->
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(s.name + if (s.enabled) " [已启用]" else "", style = MaterialTheme.typography.titleSmall)
                        Text("作者: ${s.author}  v${s.version}  平台: ${s.sources.joinToString()}", style = MaterialTheme.typography.bodySmall)
                        Row {
                            Button(onClick = { scope.launch { Api.call("music_source_toggle", mapOf("id" to s.id, "enabled" to !s.enabled)); reload() } }) {
                                Text(if (s.enabled) "停用" else "启用")
                            }
                            Spacer(Modifier.padding(4.dp))
                            Button(onClick = { scope.launch { val r = Api.call("music_source_content", mapOf("id" to s.id)); sourceDialog = r.optString("source") } }) { Text("源码") }
                            Spacer(Modifier.padding(4.dp))
                            Button(onClick = { scope.launch { Api.call("music_source_remove", mapOf("id" to s.id)); reload() } }) { Text("删除") }
                        }
                    }
                }
            }
        }
    }
    if (importDialog) MusicImportDialog(onDismiss = { importDialog = false }, onDone = { reload(); importDialog = false })
    sourceDialog?.let { TextDialog("音源源码", it) { sourceDialog = null } }
}

@Composable
private fun MusicImportDialog(onDismiss: () -> Unit, onDone: () -> Unit) {
    ImportSourceDialog(
        title = "导入音源",
        urlLabel = "音源 URL",
        onImportRemote = { Api.call("music_source_import_url", mapOf("url" to it, "enable" to true)) },
        onImportLocal = { _, source ->
            Api.call("music_source_add", mapOf("source" to source, "url" to "", "enable" to true, "sources" to emptyList<String>()))
        },
        onDismiss = onDismiss,
        onDone = onDone,
    )
}

/**
 * 统一的源导入对话框：远程导入（URL）/ 本地导入（上传本地 .js 文件）。
 * 桌面端的「粘贴源码」方式已移除。
 */
@Composable
private fun ImportSourceDialog(
    title: String,
    urlLabel: String,
    onImportRemote: suspend (String) -> JSONObject,
    onImportLocal: suspend (String, String) -> JSONObject,
    onDismiss: () -> Unit,
    onDone: () -> Unit,
) {
    var remote by remember { mutableStateOf(true) }
    var url by remember { mutableStateOf("") }
    var localName by remember { mutableStateOf<String?>(null) }
    var localSource by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val name = withContext(Dispatchers.IO) { queryDisplayName(context, uri) } ?: "source.js"
                val text = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                }
                if (text.isNullOrBlank()) {
                    err = "文件为空或读取失败"
                } else {
                    localName = name
                    localSource = text
                    err = null
                }
            }.onFailure { err = "文件读取失败: ${it.message}" }
        }
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(title) },
        text = {
            Column {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = remote,
                        onClick = { remote = true; err = null },
                        label = { Text("远程导入") },
                    )
                    FilterChip(
                        selected = !remote,
                        onClick = { remote = false; err = null },
                        label = { Text("本地导入") },
                    )
                }
                Spacer(Modifier.height(12.dp))
                if (remote) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it; err = null },
                        label = { Text(urlLabel) },
                        placeholder = { Text("https://example.com/source.js") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                } else {
                    Button(onClick = { pickFile.launch("*/*") }) {
                        Text(if (localName == null) "选择本地 JS 文件" else "重新选择文件")
                    }
                    localName?.let {
                        Spacer(Modifier.height(6.dp))
                        Text("已选择：$it", style = MaterialTheme.typography.bodyMedium)
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "从手机文件中选择一个 .js 脚本文件导入",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline,
                    )
                }
                err?.let {
                    Spacer(Modifier.height(6.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        runCatching {
                            val r = if (remote) {
                                if (url.isBlank()) throw IllegalArgumentException("请输入链接")
                                onImportRemote(url.trim())
                            } else {
                                val n = localName ?: throw IllegalArgumentException("请先选择文件")
                                val s = localSource ?: throw IllegalArgumentException("请先选择文件")
                                onImportLocal(n, s)
                            }
                            if (r.optBoolean("ok")) onDone() else err = r.optString("error", "导入失败")
                        }.onFailure { err = it.message ?: "导入失败" }
                        busy = false
                    }
                },
                enabled = !busy,
            ) { Text(if (busy) "导入中..." else "导入") }
        },
        dismissButton = { Button(onClick = onDismiss, enabled = !busy) { Text("取消") } }
    )
}

private fun queryDisplayName(context: Context, uri: Uri): String? {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
        if (c.moveToFirst()) {
            val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (i >= 0) return c.getString(i)
        }
    }
    return uri.lastPathSegment
}

@Composable
private fun TextDialog(title: String, text: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { androidx.compose.foundation.text.selection.SelectionContainer { Text(text, style = MaterialTheme.typography.bodySmall) } },
        confirmButton = { Button(onClick = onDismiss) { Text("关闭") } }
    )
}
