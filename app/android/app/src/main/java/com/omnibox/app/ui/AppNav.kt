package com.omnibox.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Source
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.omnibox.app.ui.iptv.IptvScreen
import com.omnibox.app.ui.live.LiveScreen
import com.omnibox.app.ui.music.MusicScreen
import com.omnibox.app.ui.settings.SettingsScreen
import com.omnibox.app.ui.settings.SourceManageScreen
import com.omnibox.app.ui.vod.HomeScreen
import kotlinx.coroutines.launch

data class NavItem(val label: String, val icon: @Composable () -> Unit)

/**
 * 主导航壳：6 个 tab（点播 / IPTV / 直播 / 音乐 / 源管理 / 设置）。
 * - 宽屏（平板，>=600dp）：左侧 NavigationRail 常驻
 * - 手机：顶部菜单图标 + 侧滑抽屉，点导航项后抽屉自动关闭
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppShell() {
    val items = listOf(
        NavItem("点播") { Icon(Icons.Filled.Home, null) },
        NavItem("IPTV") { Icon(Icons.Filled.LiveTv, null) },
        NavItem("直播") { Icon(Icons.Filled.Subscriptions, null) },
        NavItem("音乐") { Icon(Icons.Filled.MusicNote, null) },
        NavItem("源管理") { Icon(Icons.Filled.Source, null) },
        NavItem("设置") { Icon(Icons.Filled.Settings, null) }
    )
    var selected by rememberSaveable { mutableStateOf(0) }

    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val isTablet = LocalConfiguration.current.screenWidthDp >= 600

    val content: @Composable () -> Unit = {
        when (selected) {
            0 -> HomeScreen()
            1 -> IptvScreen()
            2 -> LiveScreen()
            3 -> MusicScreen()
            4 -> SourceManageScreen()
            5 -> SettingsScreen()
        }
    }

    if (isTablet) {
        // 平板：左侧栏常驻
        Scaffold { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                NavigationRail {
                    items.forEachIndexed { index, item ->
                        NavigationRailItem(
                            selected = selected == index,
                            onClick = { selected = index },
                            icon = item.icon,
                            label = { Text(item.label) }
                        )
                    }
                }
                Box(Modifier.weight(1f)) { content() }
            }
        }
    } else {
        // 手机：顶部菜单图标 + 侧滑抽屉
        ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                ModalDrawerSheet {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "OmniBox",
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.padding(horizontal = 28.dp, vertical = 12.dp)
                    )
                    items.forEachIndexed { index, item ->
                        NavigationDrawerItem(
                            label = { Text(item.label) },
                            icon = item.icon,
                            selected = selected == index,
                            onClick = {
                                selected = index
                                scope.launch { drawerState.close() }
                            },
                            modifier = Modifier.padding(horizontal = 12.dp)
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
        ) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(items[selected].label) },
                        navigationIcon = {
                            IconButton(onClick = { scope.launch { drawerState.open() } }) {
                                Icon(Icons.Filled.Menu, contentDescription = "打开导航菜单")
                            }
                        }
                    )
                }
            ) { padding ->
                Box(Modifier.fillMaxSize().padding(padding)) { content() }
            }
        }
    }
}
