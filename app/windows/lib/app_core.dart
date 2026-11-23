import 'dart:async';
import 'package:flutter/material.dart';
import 'ffi_client.dart';

/// 全局 API 单例（在 main 里初始化数据目录后使用）
class Api {
  static late OmniBoxApi _api;
  static void init(String dataDir) {
    _api = OmniBoxApi(OmniBoxApi.defaultPath());
    _api.initSync(dataDir);
  }
  static OmniBoxApi get i => _api;
}

/// 影视条目（搜索/详情/历史通用）
class Vod {
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String source;
  Vod({
    required this.id,
    required this.name,
    required this.pic,
    this.remarks = '',
    this.source = '',
  });

  factory Vod.fromJson(Map<String, dynamic> j) => Vod(
        id: (j['vod_id'] ?? j['id'] ?? '').toString(),
        name: (j['vod_name'] ?? j['title'] ?? '未知').toString(),
        pic: (j['vod_pic'] ?? j['pic'] ?? '').toString(),
        remarks: (j['vod_remarks'] ?? j['vod_subtitle'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
      );
}

/// 剧集（播放入口：q 为 base64 编码的 playId）
class Episode {
  final String name;
  final String q;
  Episode(this.name, this.q);
}

/// 弹幕搜索结果条目（弹弹play 兼容 API）
class DanmuEpisode {
  final String id;
  final String title;
  final String anime;
  DanmuEpisode({required this.id, required this.title, required this.anime});
  factory DanmuEpisode.fromJson(Map<String, dynamic> j) => DanmuEpisode(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        anime: (j['anime'] ?? '').toString(),
      );
}

/// 单条弹幕：time 秒 / mode 1~3 滚动 4 底部 5 顶部 / color #rrggbb / text
class DanmuItem {
  final double time;
  final int mode;
  final String color;
  final String text;
  DanmuItem({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });
  factory DanmuItem.fromJson(Map<String, dynamic> j) => DanmuItem(
        time: (j['time'] is num ? j['time'] as num : num.tryParse('${j['time']}') ?? 0).toDouble(),
        mode: (j['mode'] is num ? j['mode'] as num : num.tryParse('${j['mode']}') ?? 1).toInt(),
        color: (j['color'] ?? '#ffffff').toString(),
        text: (j['text'] ?? '').toString(),
      );
}

/// 弹幕 API 封装（走 Rust 内核 FFI，apiBase 为空用内置默认镜像）
class DanmuApi {
  static Future<List<DanmuEpisode>> search(String keyword, {String apiBase = ''}) async {
    final r = await Api.i.call('danmu_search', {
      'keyword': keyword,
      if (apiBase.isNotEmpty) 'api_base': apiBase,
    });
    if (r['ok'] != true) throw Exception((r['error'] ?? '弹幕搜索失败').toString());
    final list = r['list'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(DanmuEpisode.fromJson).toList();
  }

  static Future<List<DanmuItem>> load(String id, {String apiBase = ''}) async {
    final r = await Api.i.call('danmu_load', {
      'id': id,
      if (apiBase.isNotEmpty) 'api_base': apiBase,
    });
    if (r['ok'] != true) throw Exception((r['error'] ?? '弹幕加载失败').toString());
    final list = r['list'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(DanmuItem.fromJson).toList();
  }
}

/// 网络图片：通过 FFI 取字节（带防盗链），失败显示占位。
/// 用 StatefulWidget + Api.i.image()，Key 用 url 避免列表复用错乱。
class NetImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  NetImage(this.url, {this.width, this.height, this.fit = BoxFit.cover, this.placeholder, Key? key})
      : super(key: key);

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  ImageBytes? _img;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() { _loading = true; _img = null; });
    final img = await Api.i.image(widget.url);
    if (mounted) setState(() { _img = img; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_img != null) {
      return Image.memory(
        _img!.bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.shade300,
      child: widget.placeholder ?? const Icon(Icons.movie, color: Colors.grey),
    );
  }
}

/// 来源标签
class SourceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  SourceChip(this.label, {this.selected = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
