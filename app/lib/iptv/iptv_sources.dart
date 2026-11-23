// IPTV 源持久化 + 内容加载（dart:io + JSON，零新增依赖）。
// 源文件列表存到 <dataDir>/iptv_sources.json，结构对齐 Nexus 的 iptvSources：
//   name / type(network|file) / url / filePath / fileName / autoUpdate
// 网络源用 HttpClient 拉取 M3U 文本（带 UA + 超时），文件源直接读本地路径。
import 'dart:convert';
import 'dart:io';

import 'm3u_parser.dart';

class IptvSource {
  final String name;
  final String type; // network | file
  final String url;
  final String filePath;
  final String fileName;
  final bool autoUpdate;

  const IptvSource({
    required this.name,
    required this.type,
    this.url = '',
    this.filePath = '',
    this.fileName = '',
    this.autoUpdate = false,
  });

  bool get isNetwork => type == 'network';

  Map<String, String> toJson() => {
        'name': name,
        'type': type,
        'url': url,
        'filePath': filePath,
        'fileName': fileName,
        'autoUpdate': autoUpdate.toString(),
      };

  factory IptvSource.fromJson(Map<dynamic, dynamic> m) => IptvSource(
        name: (m['name'] ?? '').toString(),
        type: (m['type'] ?? 'network').toString(),
        url: (m['url'] ?? '').toString(),
        filePath: (m['filePath'] ?? '').toString(),
        fileName: (m['fileName'] ?? '').toString(),
        autoUpdate: m['autoUpdate']?.toString() == 'true',
      );
}

class IptvStore {
  IptvStore._();
  static final IptvStore i = IptvStore._();

  String _filePath = '';
  final List<IptvSource> sources = <IptvSource>[];

  /// main() 拿到 dataDir 后调用（与 AppSettings 同一个数据目录）
  void init(String dataDir) {
    _filePath = '${dataDir}${Platform.pathSeparator}iptv_sources.json';
    _load();
  }

  void _load() {
    if (_filePath.isEmpty) return;
    try {
      final f = File(_filePath);
      if (!f.existsSync()) return;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is List) {
        sources
          ..clear()
          ..addAll(decoded
              .whereType<Map<dynamic, dynamic>>()
              .map(IptvSource.fromJson));
      }
    } catch (_) {
      // 配置损坏则忽略，保持空列表
    }
  }

  void _save() {
    if (_filePath.isEmpty) return;
    try {
      final f = File(_filePath);
      if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(sources.map((s) => s.toJson()).toList()));
    } catch (_) {
      // 写失败不影响本次运行
    }
  }

  void add(IptvSource s) {
    sources.add(s);
    _save();
  }

  void update(int index, IptvSource s) {
    if (index < 0 || index >= sources.length) return;
    sources[index] = s;
    _save();
  }

  void remove(int index) {
    if (index < 0 || index >= sources.length) return;
    sources.removeAt(index);
    _save();
  }

  /// 读取某个源的 M3U 文本内容。失败时抛异常，由调用方决定提示方式（fail-fast）。
  Future<String> loadContent(int index) async {
    if (index < 0 || index >= sources.length) {
      throw Exception('IPTV 源索引无效: $index');
    }
    final src = sources[index];
    if (!src.isNetwork) {
      final path = src.filePath;
      if (path.isEmpty) throw Exception('文件源未设置路径');
      final f = File(path);
      if (!f.existsSync()) throw Exception('文件不存在: $path');
      return f.readAsString();
    }

    final url = src.url.trim();
    if (url.isEmpty) throw Exception('网络源未设置 URL');
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set('User-Agent', 'OmniBox/1.0 (IPTV)');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final body = await utf8.decoder.bind(resp).join();
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// 读取并解析某个源的频道列表。
  Future<List<M3uChannel>> loadChannels(int index) async {
    final content = await loadContent(index);
    return M3uParser.parse(content);
  }
}
