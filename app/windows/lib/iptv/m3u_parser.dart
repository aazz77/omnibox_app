/// M3U / M3U8 解析器（对齐 Nexus 的 parser/m3u_parser.dart）。
/// 同时支持扩展格式（#EXTM3U / #EXTINF）和纯 URL 逐行格式。
///
/// #EXTINF 行解析以下属性（大小写不敏感）：
///   tvg-name / title      频道名（优先 tvg-name，再 title，再逗号后文本）
///   group-title           分组，缺省「未分组」
///   tvg-logo              台标 URL
///   tvg-id                频道 ID
class M3uChannel {
  final String name;
  final String url;
  final String group;
  final String logo;
  final String id;

  const M3uChannel({
    required this.name,
    required this.url,
    this.group = '未分组',
    this.logo = '',
    this.id = '',
  });
}

class M3uParser {
  static List<M3uChannel> parse(String content) {
    // 兼容 UTF-8 BOM
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    final lines = content.split(RegExp(r'\r?\n'));
    final channels = <M3uChannel>[];

    String name = '', group = '未分组', logo = '', id = '';

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;

      if (line.startsWith('#EXTINF:')) {
        name = _attr(line, 'tvg-name') ??
            _attr(line, 'title') ??
            _commaName(line);
        group = _attr(line, 'group-title') ?? '未分组';
        logo = _attr(line, 'tvg-logo') ?? '';
        id = _attr(line, 'tvg-id') ?? '';
      } else if (!line.startsWith('#')) {
        channels.add(M3uChannel(
          name: name.isEmpty ? _guessName(line) : name,
          url: line,
          group: group,
          logo: logo,
          id: id,
        ));
        name = '';
        group = '未分组';
        logo = '';
        id = '';
      }
    }
    return channels;
  }

  static String? _attr(String line, String key) {
    final m = RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line);
    return m?.group(1)?.trim();
  }

  static String _commaName(String line) {
    final idx = line.lastIndexOf(',');
    return idx < 0 ? '' : line.substring(idx + 1).trim();
  }

  static String _guessName(String url) {
    try {
      final seg = Uri.parse(url).pathSegments;
      if (seg.isEmpty) return url;
      return seg.last.split('.').first;
    } catch (_) {
      return url;
    }
  }

  /// 按 group-title 分组，保持插入顺序。
  static Map<String, List<M3uChannel>> groupBy(List<M3uChannel> channels) {
    final map = <String, List<M3uChannel>>{};
    for (final ch in channels) {
      map.putIfAbsent(ch.group, () => []).add(ch);
    }
    return map;
  }
}
