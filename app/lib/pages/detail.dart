import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_core.dart';
import '../settings.dart';
import '../player/media_player.dart';
import '../player/vlc_player.dart';

/// 详情/播放页：影片信息 + 剧集列表 + media_kit 播放器
class DetailPage extends StatefulWidget {
  final Vod vod;
  DetailPage({required this.vod, Key? key}) : super(key: key);
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _loading = true;
  String? _error;
  String _name = '';
  String _pic = '';
  String _desc = '';
  List<Episode> _episodes = [];
  int _curEp = -1;
  String? _playUrl;
  Map<String, dynamic> _playHeader = {};
  bool _playing = false;
  String? _playError;
  // 弹幕：当前加载的弹幕列表 + 来源标签（显示在当前集播放器上）
  List<DanmuItem> _danmuItems = [];
  String _danmuLabel = '';
  // VLC 全屏：GlobalKey 让 VlcPlayer 的 State 在 7:3↔全屏 间移动而非重建（防黑屏）
  bool _immersive = false;
  final GlobalKey _vlcPlayerKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _name = widget.vod.name;
    _pic = widget.vod.pic;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    final r = await Api.i.call('detail', {'src': widget.vod.source, 'id': widget.vod.id});
    if (!mounted) return;
    if (r['error'] != null) {
      setState(() { _error = r['error'].toString(); _loading = false; });
      return;
    }
    final vod = r['vod'] as Map<String, dynamic>? ?? {};
    final eps = r['episodes'] as List? ?? [];
    setState(() {
      _name = (vod['vod_name'] ?? _name).toString();
      _pic = (vod['vod_pic'] ?? _pic).toString();
      _desc = (vod['vod_content'] ?? '').toString();
      _episodes = eps.whereType<Map<String, dynamic>>().map((e) => Episode(
            (e['name'] ?? '播放').toString(),
            (e['q'] ?? '').toString(),
          )).toList();
      _loading = false;
    });
    // 记录历史（进入详情即视为观看）
    _recordHistory(0, '');
  }

  Future<void> _recordHistory(int epIndex, String epName) async {
    await Api.i.call('history_add', {
      'src': widget.vod.source,
      'id': widget.vod.id,
      'name': _name,
      'pic': _pic,
      'ep': epIndex,
      'epname': epName,
    });
  }

  Future<void> _playEp(int idx) async {
    if (idx < 0 || idx >= _episodes.length) return;
    setState(() { _playing = true; _playError = null; _curEp = idx; });
    final ep = _episodes[idx];
    final r = await Api.i.call('play', {'src': widget.vod.source, 'q': ep.q});
    if (!mounted) return;
    if (r['error'] != null || (r['url'] == null)) {
      setState(() {
        _playError = (r['error'] ?? '脚本未返回播放地址').toString();
        _playing = false;
      });
      return;
    }
    setState(() {
      _playUrl = r['url'].toString();
      _playHeader = (r['header'] as Map?)?.cast<String, dynamic>() ?? {};
      _playing = false;
    });
    _recordHistory(idx, ep.name);
  }

  /// VLC 全屏切换：键盘/按钮统一入口，切换后抢回焦点保证 Esc/F 持续可用。
  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    _focusNode.requestFocus();
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    if (e.logicalKey == LogicalKeyboardKey.escape && _immersive) {
      _toggleImmersive();
    } else if (e.logicalKey == LogicalKeyboardKey.keyF &&
        AppSettings.i.vodPlayer.value == 'vlc') {
      _toggleImmersive();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        // 全屏时隐藏 AppBar，让播放器占满整屏
        appBar: _immersive
            ? null
            : AppBar(
                title: Text(_name.isNotEmpty ? _name : '详情'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.subtitles),
                    tooltip: '弹幕搜索',
                    onPressed: _showDanmuSheet,
                  ),
                ],
              ),
        // 整页不滚动：一屏内左右 7:3 分栏；VLC 全屏时只剩播放器
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧 70%（全屏时占满）：播放区域
                  Expanded(flex: 7, child: _buildLeftPane()),
                  if (!_immersive) const VerticalDivider(width: 1, thickness: 1),
                  // 右侧 30%：影视信息 + 剧集列表（全屏时隐藏）
                  if (!_immersive) Expanded(flex: 3, child: _buildRightPane()),
                ],
              ),
      ),
    );
  }

  /// 左侧播放区：播放器占满剩余空间，底部提示错误
  Widget _buildLeftPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildPlayerBox()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('详情加载失败: $_error', style: const TextStyle(color: Colors.orange, fontSize: 12)),
          ),
      ],
    );
  }

  /// 右侧信息区：影视信息（海报/名称/来源/简介）+ 选集列表。
  /// 信息固定在上，剧集列表占满剩余空间；仅当集数过多时列表内部滚动，页面本身不滚动。
  Widget _buildRightPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImage(_pic, width: 72, height: 100)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('来源: ${widget.vod.source}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              )),
            ],
          ),
        ),
        if (_desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text('选集', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_episodes.length, (i) => ChoiceChip(
                label: Text(_episodes[i].name),
                selected: i == _curEp,
                onSelected: (_) => _playEp(i),
              )),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerBox() {
    if (_playing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_playError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('取播放地址失败: $_playError', style: const TextStyle(color: Colors.orange)),
        ),
      );
    }
    if (_playUrl != null) {
      final size = MediaQuery.sizeOf(context);
      return Center(
        child: ClipRRect(
          borderRadius: _immersive ? BorderRadius.zero : BorderRadius.circular(8),
          child: AspectRatio(
            // 全屏用屏幕宽高比占满窗口；结构不变，VlcPlayer 原生纹理不重建。
            aspectRatio: _immersive ? size.width / size.height : 16 / 9,
            child: ValueListenableBuilder<String>(
              valueListenable: AppSettings.i.vodPlayer,
              builder: (context, core, _) {
                // KeyedSubtree 保证切换内核时旧播放器被 dispose、新的重新创建
                return KeyedSubtree(
                  key: ValueKey<String>(core),
                  child: core == 'vlc'
                      ? VlcVodPlayer(
                          url: _playUrl!,
                          headers: _playHeader,
                          danmuItems: _danmuItems,
                          playerKey: _vlcPlayerKey,
                          isFullscreen: _immersive,
                          onToggleFullscreen: _toggleImmersive,
                        )
                      : MpvPlayer(url: _playUrl!, headers: _playHeader, danmuItems: _danmuItems),
                );
              },
            ),
          ),
        ),
      );
    }
    // 未选集占位：占满左侧区域
    return Container(
      color: Colors.grey.shade200,
      child: const Center(child: Icon(Icons.play_circle_outline, size: 64, color: Colors.grey)),
    );
  }

  /// 弹幕搜索弹窗：关键词搜索 → 剧集列表 → 选集加载弹幕到当前播放器
  void _showDanmuSheet() {
    showDialog(
      context: context,
      builder: (_) => DanmuSearchDialog(
        initialKeyword: _name,
        currentLabel: _danmuLabel,
        onSelected: (items, label) {
          setState(() {
            _danmuItems = items;
            _danmuLabel = label;
          });
        },
        onClear: () {
          setState(() {
            _danmuItems = [];
            _danmuLabel = '';
          });
        },
      ),
    );
  }
}

/// 弹幕搜索弹窗（独立 widget，自带搜索/选集/加载状态）
class DanmuSearchDialog extends StatefulWidget {
  final String initialKeyword;
  final String currentLabel;
  final void Function(List<DanmuItem> items, String label) onSelected;
  final VoidCallback onClear;
  const DanmuSearchDialog({
    required this.initialKeyword,
    required this.currentLabel,
    required this.onSelected,
    required this.onClear,
    Key? key,
  }) : super(key: key);
  @override
  State<DanmuSearchDialog> createState() => _DanmuSearchDialogState();
}

class _DanmuSearchDialogState extends State<DanmuSearchDialog> {
  late final TextEditingController _kwC;
  List<DanmuEpisode> _results = [];
  bool _searching = false;
  String? _message;
  String? _loadingId;

  @override
  void initState() {
    super.initState();
    _kwC = TextEditingController(text: widget.initialKeyword);
  }

  @override
  void dispose() {
    _kwC.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final kw = _kwC.text.trim();
    if (kw.isEmpty) {
      setState(() => _message = '请输入关键词');
      return;
    }
    setState(() { _searching = true; _message = null; _results = []; });
    try {
      final apiBase = AppSettings.i.danmu.value.apiBase;
      final list = await DanmuApi.search(kw, apiBase: apiBase);
      if (!mounted) return;
      setState(() {
        _results = list;
        _searching = false;
        if (list.isEmpty) _message = '未找到匹配的剧集';
      });
    } catch (e) {
      if (mounted) setState(() { _searching = false; _message = '搜索失败: $e'; });
    }
  }

  Future<void> _loadEpisode(DanmuEpisode ep) async {
    setState(() => _loadingId = ep.id);
    try {
      final apiBase = AppSettings.i.danmu.value.apiBase;
      final items = await DanmuApi.load(ep.id, apiBase: apiBase);
      if (!mounted) return;
      widget.onSelected(items, ep.title);
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载 ${items.length} 条弹幕：${ep.title}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _loadingId = null; _message = '加载失败: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('弹幕搜索'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _kwC,
                  decoration: const InputDecoration(
                    hintText: '输入影片名搜索弹幕',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searching ? null : _doSearch,
                child: const Text('搜索'),
              ),
            ]),
            const SizedBox(height: 8),
            if (widget.currentLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('当前弹幕：${widget.currentLabel}',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(onPressed: () { widget.onClear(); Navigator.pop(context); },
                      child: const Text('清空弹幕')),
                ]),
              ),
            if (_message != null)
              Text(_message!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
            if (_searching)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final ep = _results[i];
                    return ListTile(
                      dense: true,
                      title: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: ep.anime.isNotEmpty
                          ? Text(ep.anime, maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: _loadingId == ep.id
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow, size: 18),
                      onTap: () => _loadEpisode(ep),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }
}
