// 直播关注页：作为「直播」tab 的首页，显示左侧导航栏。
// 顶部搜索框 -> 内部切到搜索视图（LiveSearchView）；下方关注卡片网格 + 平台筛选 + 添加关注。
import 'package:flutter/material.dart';
import '../../live/live_api.dart';
import 'live_player_page.dart';

class LiveFollowPage extends StatefulWidget {
  /// 点击顶部搜索框：通知父级在直播 tab 内切到搜索子视图（保持左侧导航栏）
  final void Function(String initial) onSearch;
  const LiveFollowPage({required this.onSearch, Key? key}) : super(key: key);
  @override
  State<LiveFollowPage> createState() => _LiveFollowPageState();
}

class _LiveFollowPageState extends State<LiveFollowPage> {
  List<LiveSite> _sites = [];
  List<LiveFollow> _follows = [];
  String _platform = 'all'; // all / 平台 id
  String _filter = 'all';   // all / live / off
  bool _loading = true;
  bool _refreshing = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sites = await LiveApi.i.sites();
      final follows = await LiveApi.i.follows();
      if (!mounted) return;
      setState(() { _sites = sites; _follows = follows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  int get _liveCount => _follows.where((f) => f.live).length;

  List<LiveFollow> get _shown {
    var list = _follows;
    if (_platform != 'all') list = list.where((f) => f.platform == _platform).toList();
    if (_filter == 'live') list = list.where((f) => f.live).toList();
    if (_filter == 'off') list = list.where((f) => !f.live).toList();
    // 置顶优先
    return [...list]..sort((a, b) => (b.top ? 1 : 0) - (a.top ? 1 : 0));
  }

  String _siteName(String id) {
    for (final s in _sites) if (s.id == id) return s.name;
    return id;
  }

  void _openSearch([String initial = '']) {
    widget.onSearch(initial);
  }

  void _openPlayer(LiveFollow f) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LivePlayerHost(platform: f.platform, roomId: f.roomId, title: f.title, userName: f.userName),
    ));
  }

  Future<void> _addFollow() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AddFollowDialog(sites: _sites),
    );
    if (result == null) return;
    final ok = await LiveApi.i.followAdd(
      result['platform']!, result['roomId']!,
      title: result['title'] ?? '', userName: result['userName'] ?? '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已添加关注' : '添加失败')));
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('直播'), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新开播状态', onPressed: _refreshing ? null : _refresh),
      ]),
      body: Column(children: [
        // 顶部搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            readOnly: true,
            onTap: () => _openSearch(),
            decoration: InputDecoration(
              hintText: '搜索直播间 / 主播，或粘贴分享链接',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        // 平台筛选 + 状态筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('全部', _platform == 'all', () => setState(() => _platform = 'all')),
                  for (final s in _sites) _chip(s.name, _platform == s.id, () => setState(() => _platform = s.id)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _chip('全部 ${_follows.length}', _filter == 'all', () => setState(() => _filter = 'all')),
            const SizedBox(width: 6),
            _chip('直播中 ${_liveCount}', _filter == 'live', () => setState(() => _filter = 'live')),
            const SizedBox(width: 6),
            _chip('未开播 ${_follows.length - _liveCount}', _filter == 'off', () => setState(() => _filter = 'off')),
            const Spacer(),
            ElevatedButton.icon(onPressed: _addFollow, icon: const Icon(Icons.add), label: const Text('添加关注')),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: active, onSelected: (_) => onTap()),
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final list = _shown;
    if (list.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.live_tv, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('还没有关注的直播间', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        TextButton(onPressed: () => _openSearch(), child: const Text('去搜索发现主播')),
      ]));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.35,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) => _RoomCard(
        follow: list[i], siteName: _siteName(list[i].platform),
        onOpen: () => _openPlayer(list[i]),
        onTop: () async { await LiveApi.i.followTop(list[i].id, !list[i].top); _load(); },
        onDel: () async { await LiveApi.i.followDel(list[i].id); _load(); },
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final LiveFollow follow;
  final String siteName;
  final VoidCallback onOpen, onTop, onDel;
  const _RoomCard({required this.follow, required this.siteName, required this.onOpen, required this.onTop, required this.onDel});
  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onOpen, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Stack(fit: StackFit.expand, children: [
          follow.cover.isNotEmpty
              ? Image.network(follow.cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12))
              : const ColoredBox(color: Colors.black12),
          Positioned(top: 6, left: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
            child: Text(siteName, style: const TextStyle(color: Colors.white, fontSize: 11)),
          )),
          if (follow.live)
            Positioned(top: 6, right: 6, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text('直播中', style: TextStyle(color: Colors.white, fontSize: 11)),
            )),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(8, 6, 4, 4), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(follow.title.isEmpty ? follow.roomId : follow.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(follow.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          PopupMenuButton<String>(onSelected: (v) => v == 'top' ? onTop() : onDel(), itemBuilder: (_) => [
            PopupMenuItem(value: 'top', child: Text(follow.top ? '取消置顶' : '置顶')),
            const PopupMenuItem(value: 'del', child: Text('删除')),
          ]),
        ])),
      ])),
    );
  }
}

class _AddFollowDialog extends StatefulWidget {
  final List<LiveSite> sites;
  const _AddFollowDialog({required this.sites});
  @override
  State<_AddFollowDialog> createState() => _AddFollowDialogState();
}

class _AddFollowDialogState extends State<_AddFollowDialog> {
  String _platform = 'bilibili';
  final _ctrl = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.sites.isNotEmpty) _platform = widget.sites.first.id;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _ok() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) return;
    // 先尝试解析链接（含平台+房间号），解析失败则用下拉平台 + 输入作为房间号
    String platform = _platform, roomId = input;
    try {
      final parsed = await LiveApi.i.parseLink(input);
      platform = parsed['platform']!;
      roomId = parsed['roomId']!;
    } catch (_) { /* 纯房间号，用当前平台 */ }
    if (!mounted) return;
    Navigator.of(context).pop({'platform': platform, 'roomId': roomId});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加关注'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          value: _platform,
          items: [for (final s in widget.sites) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => setState(() => _platform = v ?? _platform),
          decoration: const InputDecoration(labelText: '平台'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: '房间号 / 分享链接 / 短链',
            hintText: '纯房间号用上方平台，链接会自动识别',
          ),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(onPressed: _ok, child: const Text('添加')),
      ],
    );
  }
}
