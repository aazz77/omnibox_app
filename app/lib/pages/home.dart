import 'package:flutter/material.dart';
import '../app_core.dart';
import 'search.dart';
import 'history.dart';

/// 首页：豆瓣推荐（banner 横滑 + 电影/电视剧横滑）
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<dynamic> _banners = [];
  List<Vod> _movies = [];
  List<Vod> _tv = [];
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Api.i.call('douban_home');
    if (!mounted) return;
    if (r['ok'] == true) {
      setState(() {
        _banners = r['banners'] as List? ?? [];
        final movie = r['movie'];
        final tv = r['tv'];
        _movies = _parseList(movie is Map ? movie['list'] : null);
        _tv = _parseList(tv is Map ? tv['list'] : null);
        _loading = false;
      });
    } else {
      setState(() { _error = r['error']?.toString(); _loading = false; });
    }
  }

  List<Vod> _parseList(dynamic list) {
    if (list is! List) return [];
    return list.whereType<Map<String, dynamic>>().map(Vod.fromJson).toList();
  }

  void _openDetail(Vod v, {String source = 'douban'}) {
    // 豆瓣条目：用片名去影视脚本源搜索，进入播放链路
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchPage(initialQuery: v.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text('加载失败: $_error'),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _load, child: const Text('重试')),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 历史入口（历史页改为全屏 push，不再占导航）
          Card(
            child: ListTile(
              leading: const Icon(Icons.history, color: Colors.indigo),
              title: const Text('观看历史'),
              subtitle: const Text('查看最近播放记录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('豆瓣推荐'),
          if (_banners.isNotEmpty) _bannerCarousel(),
          const SizedBox(height: 8),
          _sectionTitle('电影'),
          _posterRow(_movies),
          const SizedBox(height: 16),
          _sectionTitle('电视剧'),
          _posterRow(_tv),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _bannerCarousel() {
    return SizedBox(
      height: 160,
      child: PageView.builder(
        itemCount: _banners.length,
        itemBuilder: (_, i) {
          final b = _banners[i] as Map<String, dynamic>;
          final pic = (b['vod_pic'] ?? b['pic'] ?? '').toString();
          final name = (b['vod_name'] ?? b['title'] ?? '').toString();
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(pic, fit: BoxFit.cover),
                Container(decoration: const BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ))),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _posterRow(List<Vod> items) {
    if (items.isEmpty) return const SizedBox(height: 100, child: Center(child: Text('暂无数据')));
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final v = items[i];
          return GestureDetector(
            onTap: () => _openDetail(v),
            child: SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: NetImage(v.pic, width: 110, height: 130),
                  ),
                  const SizedBox(height: 4),
                  Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
