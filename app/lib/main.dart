import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app_core.dart';
import 'settings.dart';
import 'pages/home.dart';
import 'pages/search.dart';
import 'pages/spiders.dart';
import 'pages/iptv.dart';
import 'pages/live/live_tab_page.dart';
import 'pages/music/music_tab.dart';
import 'pages/music/music_player_page.dart';
import 'pages/settings.dart';
import 'iptv/iptv_sources.dart';
import 'music/global_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit >=1.1 必须在 runApp 前初始化，否则 libmpv 运行时崩溃
  MediaKit.ensureInitialized();
  // 数据目录：Windows 用 %APPDATA%\omnibox\data，其它用 ./data
  String dataDir;
  if (Platform.isWindows) {
    final appdata = Platform.environment['APPDATA'];
    dataDir = appdata != null ? '$appdata\\omnibox\\data' : 'data';
  } else {
    dataDir = 'data';
  }
  Api.init(dataDir);
  AppSettings.i.init(dataDir); // 读取持久化设置（解码方式等）
  IptvStore.i.init(dataDir); // 读取 IPTV 源列表
  runApp(OmniBoxApp(dataDir: dataDir));
}

class OmniBoxApp extends StatelessWidget {
  final String dataDir;
  const OmniBoxApp({required this.dataDir, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniBox',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: MainShell(dataDir: dataDir),
    );
  }
}

/// 主壳：左侧导航 + 7 个页面（用 IndexedStack 保持各页状态）。
/// 历史页 / 直播播放页为全屏 push，不在此导航内。
class MainShell extends StatefulWidget {
  final String dataDir;
  const MainShell({required this.dataDir, Key? key}) : super(key: key);
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  SearchPage _searchPage = SearchPage();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      _searchPage,
      const SpidersPage(),
      const IptvPage(),       // 原「直播」→ 现「iptv」（M3U 直播）
      const LiveTabPage(),    // 新「直播」：6 平台聚合（关注 + 搜索）
      const MusicTabPage(),
      const SettingsPage(),
    ];
  }

  /// 首页点卡片 -> 带关键词跳到搜索页并自动搜索
  void openSearch(String query) {
    setState(() {
      _searchPage = SearchPage(initialQuery: query);
      _pages[1] = _searchPage;
      _tab = 1;
    });
  }

  static const _navItems = [
    Icons.home,        // 首页（含历史入口）
    Icons.search,
    Icons.source,      // 源管理
    Icons.live_tv,     // iptv（M3U 直播）
    Icons.subscriptions, // 直播（6 平台聚合，关注 + 搜索）
    Icons.music_note,
    Icons.settings,
  ];
  static const _navLabels = ['首页', '搜索', '源管理', 'iptv', '直播', '音乐', '设置'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 用 Stack 常挂一个 1x1 隐藏 mpv 纹理，保活音乐播放管线（Nexus 踩过的坑）：
      // 即使切到别的 tab，音乐也持续推进播放，不会因为播放页 dispose 而卡住。
      body: Stack(children: [
        Row(children: [
          // 左侧导航栏（桌面端）：始终显示图标+文字
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            minWidth: 72,
            extended: false,
            leading: const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Icon(Icons.movie, color: Colors.indigo, size: 32),
            ),
            destinations: [
              for (var i = 0; i < _navItems.length; i++)
                NavigationRailDestination(
                  icon: Icon(_navItems[i]),
                  label: Text(_navLabels[i]),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: IndexedStack(index: _tab, children: _pages)),
        ]),
        const Positioned(width: 1, height: 1, child: HiddenMusicSink()),
      ]),
    );
  }
}
