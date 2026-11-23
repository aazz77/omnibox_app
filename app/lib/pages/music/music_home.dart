import 'package:flutter/material.dart';
import '../../music/music_api.dart';

/// 音乐首页：顶部搜索框 + 热搜 + 平台切换 + 排行榜卡片网格。
/// onOpenBoard 回调进入榜单歌曲列表页，onSearch 回调进入搜索页。
class MusicHomePage extends StatefulWidget {
  final Function(MusicBoard board) onOpenBoard;
  final Function(String keyword) onSearch;
  const MusicHomePage({required this.onOpenBoard, required this.onSearch, Key? key}) : super(key: key);

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  String _platform = 'kw';
  final TextEditingController _searchCtrl = TextEditingController();
  List<MusicBoard> _boards = [];
  List<String> _hot = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        MusicApi.boards(source: _platform),
        MusicApi.hotSearch(source: _platform),
      ]);
      if (!mounted) return;
      setState(() {
        _boards = results[0] as List<MusicBoard>;
        _hot = results[1] as List<String>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _switchPlatform(String key) {
    if (key == _platform) return;
    setState(() => _platform = key);
    _load();
  }

  void _doSearch() {
    final kw = _searchCtrl.text.trim();
    if (kw.isNotEmpty) widget.onSearch(kw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '搜索歌曲、歌手、专辑',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() {}); })
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onSubmitted: (_) => _doSearch(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _doSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ]),
            ),
            // 热搜词
            if (_hot.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
                  for (final h in _hot.take(10))
                    ActionChip(
                      label: Text(h, style: const TextStyle(fontSize: 12)),
                      onPressed: () { _searchCtrl.text = h; widget.onSearch(h); },
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              ),
            // 平台切换
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                const Text('排行榜', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: [for (final p in MusicPlatform.all) ButtonSegment(value: p.key, label: Text(p.label))],
                  selected: {_platform},
                  onSelectionChanged: (s) => _switchPlatform(s.first),
                ),
              ]),
            ),
            const Divider(height: 1),
            // 榜单网格
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('加载失败: $_error', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('重试')),
                        ]))
                      : _boards.isEmpty
                          ? const Center(child: Text('暂无榜单数据'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 1.5,
                              ),
                              itemCount: _boards.length,
                              itemBuilder: (context, i) {
                                final b = _boards[i];
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => widget.onOpenBoard(b),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.indigo.shade50, Colors.white],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(children: [
                                            Icon(Icons.leaderboard, color: Colors.indigo.shade400, size: 22),
                                            const Spacer(),
                                            Text(b.bangid, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                          ]),
                                          Text(b.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
