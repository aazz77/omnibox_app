// 直播搜索子视图：在「直播」tab 内与关注页切换，保持左侧导航栏。
// 平台选择 + 关键词 + 直播间/主播切换 + 结果卡片（关注/播放）+ 分页。
import 'package:flutter/material.dart';
import '../../live/live_api.dart';
import 'live_player_page.dart';

class LiveSearchView extends StatefulWidget {
  final List<LiveSite> sites;
  final String initialKeyword;
  final VoidCallback onBack;
  const LiveSearchView({required this.sites, this.initialKeyword = '', required this.onBack, Key? key}) : super(key: key);
  @override
  State<LiveSearchView> createState() => _LiveSearchViewState();
}

class _LiveSearchViewState extends State<LiveSearchView> {
  final _ctrl = TextEditingController();
  String _platform = 'bilibili';
  bool _anchor = false;
  List<LiveSearchItem> _items = [];
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  String? _err;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialKeyword;
    if (widget.sites.isNotEmpty) {
      final first = widget.sites.firstWhere((s) => s.searchable, orElse: () => widget.sites.first);
      _platform = first.id;
    }
    if (widget.initialKeyword.trim().isNotEmpty) _doSearch(1);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _doSearch(int page) async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) return;
    setState(() { _loading = true; _err = null; });
    try {
      final r = await LiveApi.i.search(_platform, kw, page: page, anchor: _anchor);
      if (!mounted) return;
      setState(() {
        _items = ((r['items'] as List?) ?? []).map((e) => LiveSearchItem.fromJson(e as Map<String, dynamic>)).toList();
        _hasMore = r['hasMore'] as bool? ?? false;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _loading = false; });
    }
  }

  Future<void> _follow(LiveSearchItem it) async {
    final ok = await LiveApi.i.followAdd(_platform, it.roomId, title: it.title, userName: it.userName, cover: it.cover);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已关注「${it.userName.isEmpty ? it.roomId : it.userName}」' : '关注失败')));
  }

  void _openPlayer(LiveSearchItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LivePlayerHost(platform: _platform, roomId: it.roomId, title: it.title, userName: it.userName),
    ));
  }

  List<LiveSite> get _searchable => widget.sites.where((s) => s.searchable).toList();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // 头部：返回 + 标题
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          const Text('搜索', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
      // 搜索栏
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Row(children: [
          SizedBox(width: 150, child: DropdownButtonFormField<String>(
            value: _platform,
            isDense: true,
            items: [for (final s in _searchable) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _platform = v ?? _platform),
            decoration: const InputDecoration(labelText: '平台', isDense: true),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _ctrl,
            onSubmitted: (_) => _doSearch(1),
            decoration: const InputDecoration(hintText: '关键词 / 主播名', border: OutlineInputBorder()),
          )),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loading ? null : () => _doSearch(1), child: const Text('搜索')),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        ChoiceChip(label: const Text('直播间'), selected: !_anchor, onSelected: (_) => setState(() => _anchor = false)),
        const SizedBox(width: 6),
        ChoiceChip(label: const Text('主播'), selected: _anchor, onSelected: (_) => setState(() => _anchor = true)),
      ])),
      if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12))),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off, size: 48, color: Colors.grey),
        const SizedBox(height: 10),
        Text(_ctrl.text.trim().isEmpty ? '输入关键词开始搜索' : '没有找到结果，换个词试试', style: const TextStyle(color: Colors.grey)),
      ]));
    }
    return Column(children: [
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final it = _items[i];
          return ListTile(
            leading: it.cover.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(it.cover, width: 84, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 84, height: 52, color: Colors.black12)))
                : Container(width: 84, height: 52, color: Colors.black12),
            title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${it.userName}${it.liveStatus ? ' · 直播中' : ''}', maxLines: 1),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => _follow(it), child: const Text('关注')),
              ElevatedButton(onPressed: () => _openPlayer(it), child: const Text('播放')),
            ]),
          );
        },
      )),
      Padding(padding: const EdgeInsets.all(8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton(onPressed: _page > 1 ? () => _doSearch(_page - 1) : null, child: const Text('上一页')),
        const SizedBox(width: 16),
        Text('第 $_page 页'),
        const SizedBox(width: 16),
        OutlinedButton(onPressed: _hasMore ? () => _doSearch(_page + 1) : null, child: const Text('下一页')),
      ])),
    ]);
  }
}
