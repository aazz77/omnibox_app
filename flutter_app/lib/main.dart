import 'dart:io';
import 'package:flutter/material.dart';
import 'app_core.dart';
import 'pages/home.dart';
import 'pages/search.dart';
import 'pages/history.dart';
import 'pages/spiders.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 数据目录：Windows 用 %APPDATA%\omnibox\data，其它用 ./data
  String dataDir;
  if (Platform.isWindows) {
    final appdata = Platform.environment['APPDATA'];
    dataDir = appdata != null ? '$appdata\\omnibox\\data' : 'data';
  } else {
    dataDir = 'data';
  }
  Api.init(dataDir);
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

/// 主壳：底部导航 + 4 个页面（用 IndexedStack 保持各页状态）
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
      const HistoryPage(),
      const SpidersPage(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '历史'),
          BottomNavigationBarItem(icon: Icon(Icons.source), label: '源管理'),
        ],
      ),
    );
  }
}
