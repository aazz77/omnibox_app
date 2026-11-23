package com.omnibox.app.ui.vod

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FilterChip
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.omnibox.app.core.ObImage
import com.omnibox.app.models.HistoryItem
import com.omnibox.app.models.Vod

/** 点播模块根：内部状态机在 首页/搜索/历史/详情 之间切换 */
@Composable
fun HomeScreen(vm: VodViewModel = viewModel()) {
    var screen by remember { mutableStateOf<VodScreen>(VodScreen.Home) }
    var searchQuery by remember { mutableStateOf("") }
    var detailVod by remember { mutableStateOf<Vod?>(null) }

    when (val s = screen) {
        VodScreen.Home -> HomeContent(
            vm = vm,
            onSearch = { q -> searchQuery = q; screen = VodScreen.Search },
            onHistory = { screen = VodScreen.History },
            onVod = { searchQuery = it.name; screen = VodScreen.Search }
        )
        VodScreen.Search -> SearchContent(
            vm = vm,
            initialQuery = searchQuery,
            onBack = { screen = VodScreen.Home },
            onDetail = { detailVod = it; screen = VodScreen.Detail }
        )
        VodScreen.History -> HistoryContent(
            vm = vm,
            onBack = { screen = VodScreen.Home },
            onVod = { detailVod = it; screen = VodScreen.Detail }
        )
        VodScreen.Detail -> detailVod?.let { vod ->
            DetailContent(vm = vm, vod = vod, onBack = { screen = VodScreen.Home })
        } ?: run { screen = VodScreen.Home }
    }
}

private sealed class VodScreen { object Home : VodScreen(); object Search : VodScreen(); object History : VodScreen(); object Detail : VodScreen() }

@Composable
private fun HomeContent(
    vm: VodViewModel,
    onSearch: (String) -> Unit,
    onHistory: () -> Unit,
    onVod: (Vod) -> Unit
) {
    val banners by vm.banners.collectAsStateWithLifecycle()
    val movies by vm.movies.collectAsStateWithLifecycle()
    val tv by vm.tv.collectAsStateWithLifecycle()
    val loading by vm.loading.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { if (banners.isEmpty() && movies.isEmpty()) vm.loadHome() }

    var query by remember { mutableStateOf("") }
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        item {
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = query, onValueChange = { query = it },
                placeholder = { Text("搜索影视") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                trailingIcon = { Button(onClick = { onSearch(query) }) { Text("搜索") } },
                modifier = Modifier.fillMaxWidth(), singleLine = true
            )
            Spacer(Modifier.height(8.dp))
            Card(modifier = Modifier.fillMaxWidth().clickable { onHistory() }) {
                ListItem(
                    headlineContent = { Text("观看历史") },
                    leadingContent = { Icon(Icons.Filled.History, null) }
                )
            }
            if (error != null) {
                Text("加载失败: $error", color = MaterialTheme.colorScheme.error)
                Button(onClick = { vm.loadHome() }) { Text("重试") }
            }
            if (loading && banners.isEmpty()) {
                Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            Spacer(Modifier.height(8.dp))
            Text("豆瓣推荐", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(6.dp))
        }
        if (banners.isNotEmpty()) {
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(banners) { v ->
                        Box(Modifier.width(240.dp).height(140.dp).clickable { onVod(v) }) {
                            ObImage(v.pic, Modifier.fillMaxSize())
                            Box(Modifier.align(Alignment.BottomStart).padding(8.dp)) {
                                Text(v.name, color = androidx.compose.ui.graphics.Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
        if (movies.isNotEmpty()) {
            item { Text("电影", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(6.dp)) }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(movies) { v -> PosterCard(v, onVod) }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
        if (tv.isNotEmpty()) {
            item { Text("电视剧", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(6.dp)) }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(tv) { v -> PosterCard(v, onVod) }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

@Composable
private fun PosterCard(vod: Vod, onClick: (Vod) -> Unit) {
    Column(Modifier.width(110.dp).clickable { onClick(vod) }) {
        ObImage(vod.pic, Modifier.fillMaxWidth().height(150.dp))
        Spacer(Modifier.height(4.dp))
        Text(vod.name, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun SearchContent(
    vm: VodViewModel,
    initialQuery: String,
    onBack: () -> Unit,
    onDetail: (Vod) -> Unit
) {
    val results by vm.results.collectAsStateWithLifecycle()
    val sources by vm.sources.collectAsStateWithLifecycle()
    val hasMore by vm.searchHasMore.collectAsStateWithLifecycle()
    val loading by vm.loading.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf(initialQuery) }
    var src by remember { mutableStateOf("all") }
    var searched by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.loadSources() }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = onBack) { Text("返回") }
            Spacer(Modifier.width(8.dp))
            OutlinedTextField(
                value = query, onValueChange = { query = it },
                placeholder = { Text("输入片名") }, modifier = Modifier.weight(1f), singleLine = true
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { searched = true; vm.search(src, query, 1) }) { Text("搜索") }
        }
        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            item { FilterChip(onClick = { src = "all" }, label = { Text("全部") }, selected = src == "all") }
            items(sources) { s ->
                FilterChip(onClick = { src = s.id }, label = { Text(s.displayName) }, selected = src == s.id)
            }
        }
        Spacer(Modifier.height(8.dp))
        if (loading && results.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (searched && results.isEmpty() && !loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("没有找到结果") }
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                itemsIndexed(results) { _, v ->
                    ListItem(
                        headlineContent = { Text(v.name) },
                        supportingContent = { Text("${v.source} ${v.remarks}") },
                        leadingContent = { ObImage(v.pic, Modifier.width(56.dp).height(80.dp)) },
                        modifier = Modifier.clickable { onDetail(v) }
                    )
                }
                if (hasMore) {
                    item {
                        Button(
                            onClick = { vm.search(src, query, vm.results.value.size / 20 + 1) },
                            modifier = Modifier.fillMaxWidth().padding(8.dp)
                        ) { Text("下一页") }
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryContent(
    vm: VodViewModel,
    onBack: () -> Unit,
    onVod: (Vod) -> Unit
) {
    val history by vm.history.collectAsStateWithLifecycle()
    val loading by vm.loading.collectAsStateWithLifecycle()
    var confirmClear by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.loadHistory() }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = onBack) { Text("返回") }
            Spacer(Modifier.weight(1f))
            if (history.isNotEmpty()) Button(onClick = { confirmClear = true }) { Text("清空") }
        }
        if (confirmClear) {
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { confirmClear = false },
                title = { Text("清空历史") },
                text = { Text("确定清空所有播放历史吗？") },
                confirmButton = { Button(onClick = { vm.clearHistory(); confirmClear = false }) { Text("清空") } },
                dismissButton = { Button(onClick = { confirmClear = false }) { Text("取消") } }
            )
        }
        if (loading && history.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (history.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("暂无播放历史") }
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                items(history, key = { it.key }) { h ->
                    HistoryRow(h, onVod, onRemove = { vm.removeHistory(h.key) })
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(h: HistoryItem, onVod: (Vod) -> Unit, onRemove: () -> Unit) {
    ListItem(
        headlineContent = { Text(h.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        supportingContent = { Text("${h.src} · ${h.epName}") },
        leadingContent = { ObImage(h.pic, Modifier.width(56.dp).height(80.dp)) },
        trailingContent = { IconButton(onClick = onRemove) { Icon(Icons.Filled.Close, "删除") } },
        modifier = Modifier.clickable {
            onVod(Vod(id = h.vodId, name = h.name, pic = h.pic, source = h.src))
        }
    )
}
