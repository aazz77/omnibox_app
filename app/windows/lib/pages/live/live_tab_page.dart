// 直播 tab 容器：在「关注」（首页）与「搜索」子视图间切换，两者都保留左侧导航栏。
// 播放页由子视图 push 全屏打开，不经此容器。
import 'package:flutter/material.dart';
import '../../live/live_api.dart';
import 'live_follow_page.dart';
import 'live_search_view.dart';

class LiveTabPage extends StatefulWidget {
  const LiveTabPage({Key? key}) : super(key: key);
  @override
  State<LiveTabPage> createState() => _LiveTabPageState();
}

class _LiveTabPageState extends State<LiveTabPage> {
  int _view = 0; // 0 关注 / 1 搜索
  List<LiveSite> _sites = [];
  String _initialKw = '';

  @override
  void initState() {
    super.initState();
    LiveApi.i.sites().then((s) {
      if (mounted) setState(() => _sites = s);
    }).catchError((_) {});
  }

  void _toSearch(String kw) {
    setState(() { _initialKw = kw; _view = 1; });
  }

  @override
  Widget build(BuildContext context) {
    if (_view == 1) {
      return LiveSearchView(
        sites: _sites,
        initialKeyword: _initialKw,
        onBack: () => setState(() => _view = 0),
      );
    }
    return LiveFollowPage(onSearch: _toSearch);
  }
}
