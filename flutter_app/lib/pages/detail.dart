import 'package:flutter/material.dart';
import '../app_core.dart';
import '../player/media_player.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_name.isNotEmpty ? _name : '详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImage(_pic, width: 110, height: 150)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('来源: ${widget.vod.source}'),
                        ],
                      )),
                    ],
                  ),
                  if (_desc.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                  const SizedBox(height: 12),
                  _buildPlayerBox(),
                  const SizedBox(height: 16),
                  const Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Text('详情加载失败: $_error', style: const TextStyle(color: Colors.orange)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_episodes.length, (i) => ChoiceChip(
                      label: Text(_episodes[i].name),
                      selected: i == _curEp,
                      onSelected: (_) => _playEp(i),
                    )),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPlayerBox() {
    if (_playing) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_playError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.orange.shade50,
        child: Text('取播放地址失败: $_playError', style: const TextStyle(color: Colors.orange)),
      );
    }
    if (_playUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MpvPlayer(url: _playUrl!, headers: _playHeader),
        ),
      );
    }
    return Container(
      height: 180,
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
      child: const Center(child: Icon(Icons.play_circle_outline, size: 56, color: Colors.grey)),
    );
  }
}
