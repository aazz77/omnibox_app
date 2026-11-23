import '../app_core.dart';
import '../settings.dart';

/// 音乐平台（内置 SDK 支持：kw 酷我 / kg 酷狗 / qq / wy 网易）
class MusicPlatform {
  final String key;
  final String label;
  const MusicPlatform(this.key, this.label);
  static const all = [
    MusicPlatform('kw', '酷我'),
    MusicPlatform('kg', '酷狗'),
    MusicPlatform('qq', 'QQ音乐'),
    MusicPlatform('wy', '网易云'),
  ];
}

/// 音质管理与智能降级（对齐 lx-server 的 quality.js）
class MusicQuality {
  /// 音质优先级（从高到低）
  static const List<String> priority = ['flac24bit', 'flac', '320k', '128k'];
  /// 显示名
  static const Map<String, String> names = {
    'flac24bit': 'Hi-Res',
    'flac': '无损',
    '320k': '高品质',
    '128k': '标准',
  };

  static String label(String q) => names[q] ?? q.toUpperCase();

  /// 从用户偏好开始、按歌曲实际支持的 types 向下降级，返回最佳可用音质。
  /// 若歌曲无音质信息，按偏好原样返回（交给音源脚本尝试）。
  static String best(MusicSong song, String preference) {
    int start = priority.indexOf(preference);
    if (start < 0) start = priority.indexOf(AppSettings.defaultMusicQuality);
    if (start < 0) start = priority.length - 1;
    if (song.types.isEmpty) return priority[start];
    for (int i = start; i < priority.length; i++) {
      if (song.types.contains(priority[i])) return priority[i];
    }
    // 偏好档位都不支持：取歌曲支持的第一个（按优先级排序）
    for (final q in priority) {
      if (song.types.contains(q)) return q;
    }
    return song.types.first;
  }

  /// 下一级更低音质（用于播放失败降级重试），到最低返回 null
  static String? nextLower(String current) {
    final i = priority.indexOf(current);
    if (i < 0 || i >= priority.length - 1) return null;
    return priority[i + 1];
  }
}

/// 排行榜（榜单卡片）
class MusicBoard {
  final String id;
  final String name;
  final String bangid;
  final String source;
  MusicBoard({required this.id, required this.name, required this.bangid, required this.source});
  factory MusicBoard.fromJson(Map<String, dynamic> j) => MusicBoard(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '未知榜单').toString(),
        bangid: (j['bangid'] ?? '').toString(),
        source: (j['source'] ?? 'kw').toString(),
      );
}

/// 歌曲（榜单 / 搜索通用）
class MusicSong {
  final String source;
  final String songmid;
  final String name;
  final String singer;
  final String albumName;
  final String albumId;
  final String interval;
  final String hash;
  final String picUrl;
  /// 歌曲支持的音质列表（如 128k/320k/flac/flac24bit），用于按偏好智能降级
  final List<String> types;
  /// MV id：酷狗为 mvhash 字符串，网易为数值 id 字符串；空/"0" 表示无 MV。
  /// 仅内置 SDK 的 wy/kg 支持 MV 播放（对齐 FMusic）。
  final String mv;

  MusicSong({
    required this.source,
    required this.songmid,
    required this.name,
    this.singer = '',
    this.albumName = '',
    this.albumId = '',
    this.interval = '',
    this.hash = '',
    this.picUrl = '',
    this.types = const [],
    this.mv = '',
  });

  /// 稳定唯一 key（用于队列去重/定位）
  String get uid => '${source}_${songmid}_$name';

  /// 该歌曲是否可能带 MV（仅 wy/kg；网易 "0" 与空串视为无）。
  /// 注意：搜索接口常把 mv 置 "0"，需用 MusicApi.mvInfo 补全后再判断。
  bool get mvSupported => source == 'wy' || source == 'kg';
  bool get hasMv => mvSupported && mv.isNotEmpty && mv != '0';

  factory MusicSong.fromJson(Map<String, dynamic> j) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v != null && v.toString().isNotEmpty && v.toString() != 'null') return v.toString();
      }
      return '';
    }
    return MusicSong(
      source: pick(['source']).isEmpty ? 'kw' : pick(['source']),
      songmid: pick(['songmid', 'songId', 'musicId', 'id']),
      name: pick(['name', 'songName', 'title']),
      singer: pick(['singer', 'artist', 'author']),
      albumName: pick(['albumName', 'album', 'album_name']),
      albumId: pick(['albumId', 'albumMid']),
      interval: pick(['interval', 'duration']),
      hash: pick(['hash']),
      picUrl: pick(['picUrl', 'img', 'pic', 'picture']),
      types: _parseTypes(j),
      mv: pick(['mv', 'mvhash', 'mvId', 'mv_id', 'videoId']),
    );
  }

  /// SDK 的 types 字段有两种形态：
  ///  - 数组: [{type:'320k', size:'..'}, ...] 或 ['320k','flac']
  ///  - 对象: {'320k': true, 'flac': {...}}
  /// 同时兼容 _types / qualitys / meta.types（对齐 lx-server quality.js）。
  static List<String> _parseTypes(Map<String, dynamic> j) {
    dynamic raw = j['types'] ?? j['_types'] ?? j['qualitys'] ?? j['_qualitys'];
    if (raw == null) {
      final meta = j['meta'];
      if (meta is Map) {
        raw = meta['types'] ?? meta['_types'] ?? meta['qualitys'] ?? meta['_qualitys'];
      }
    }
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          out.add(e);
        } else if (e is Map) {
          final t = e['type'] ?? e['name'];
          if (t != null) out.add(t.toString());
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        final ok = v == true || (v is num && v > 0) || v is Map || (v is String && v.isNotEmpty && v != 'false');
        if (ok) out.add(k.toString());
      });
    }
    return out.where((t) => t.isNotEmpty).toList();
  }

  /// 传给 Rust 内核的稀疏歌曲信息
  Map<String, dynamic> toInfo() => {
        'source': source,
        'songmid': songmid,
        'songId': songmid,
        'name': name,
        'singer': singer,
        'albumName': albumName,
        'albumId': albumId,
        'interval': interval,
        'hash': hash,
        'types': types,
        'mv': mv,
        if (picUrl.isNotEmpty) 'picUrl': picUrl,
      };
}

/// 音源条目
class MusicSource {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String homepage;
  final bool enabled;
  final List<String> sources;
  final int size;
  MusicSource({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '',
    this.author = '',
    this.homepage = '',
    this.enabled = false,
    this.sources = const [],
    this.size = 0,
  });
  factory MusicSource.fromJson(Map<String, dynamic> j) => MusicSource(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '未命名音源').toString(),
        description: (j['description'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
        homepage: (j['homepage'] ?? '').toString(),
        enabled: j['enabled'] as bool? ?? false,
        sources: (j['sources'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        size: (j['size'] is num ? j['size'] as num : 0).toInt(),
      );
}

/// 音乐 API（全部走 Rust 内核 FFI）
class MusicApi {
  static List<MusicBoard> _boardsOf(Map<String, dynamic> r) {
    final list = r['list'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(MusicBoard.fromJson).toList();
  }
  static List<MusicSong> _songsOf(Map<String, dynamic> r) {
    final list = r['list'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(MusicSong.fromJson).toList();
  }

  static Future<List<MusicBoard>> boards({String source = 'kw'}) async {
    final r = await Api.i.call('music_boards', {'source': source});
    if (r['ok'] == false && r['list'] == null) throw Exception((r['error'] ?? '获取榜单失败').toString());
    return _boardsOf(r);
  }

  static Future<List<MusicSong>> boardList(String bangid, {String source = 'kw', int page = 1}) async {
    final r = await Api.i.call('music_board_list', {'source': source, 'bangid': bangid, 'page': page});
    if (r['ok'] == false && r['list'] == null) throw Exception((r['error'] ?? '获取榜内歌曲失败').toString());
    return _songsOf(r);
  }

  static Future<List<MusicSong>> search(String keyword, {String source = 'kw', int page = 1, int limit = 30}) async {
    final r = await Api.i.call('music_search', {
      'source': source, 'keyword': keyword, 'page': page, 'limit': limit,
    });
    if (r['ok'] == false && r['list'] == null) throw Exception((r['error'] ?? '搜索失败').toString());
    return _songsOf(r);
  }

  static Future<List<String>> hotSearch({String source = 'kw'}) async {
    final r = await Api.i.call('music_hot_search', {'source': source});
    if (r['ok'] == false) return const [];
    // SDK 返回结构不一：{list:[{name}]} 或 {data:[...]}，做宽松解析
    final list = (r['list'] ?? r['data']) as List? ?? [];
    return list.map((e) {
      if (e is String) return e;
      if (e is Map) return (e['name'] ?? e['keyword'] ?? '').toString();
      return '';
    }).where((s) => s.isNotEmpty).toList();
  }

  /// 播放链接：需要先导入并启用音源脚本。
  /// quality 缺省时用「设置 → 音乐音质」的偏好，并按歌曲支持 types 智能降级。
  static Future<MusicUrlResult> url(MusicSong song, {String? quality}) async {
    final q = quality ?? MusicQuality.best(song, AppSettings.i.preferredQuality.value);
    final r = await Api.i.call('music_url', {'songInfo': song.toInfo(), 'quality': q});
    if (r['ok'] != true || (r['url'] ?? '').toString().isEmpty) {
      throw Exception((r['error'] ?? '未找到播放链接，请先导入并启用音源').toString());
    }
    return MusicUrlResult(
      url: r['url'].toString(),
      type: (r['type'] ?? q).toString(),
      sourceName: (r['sourceName'] ?? '').toString(),
    );
  }

  static Future<String> lyric(MusicSong song) async {
    final r = await Api.i.call('music_lyric', {'songInfo': song.toInfo()});
    if (r['ok'] == false && r['lyric'] == null) return '';
    final main = (r['lyric'] ?? '').toString();
    final trans = (r['tlyric'] ?? '').toString();
    if (trans.isEmpty || trans == main) return main;
    return '$main\n$trans';
  }

  static Future<String> pic(MusicSong song) async {
    if (song.picUrl.startsWith('http')) return song.picUrl;
    final r = await Api.i.call('music_pic', {'songInfo': song.toInfo()});
    return (r['url'] ?? '').toString();
  }

  // ---- MV（仅 wy/kg，内置 SDK 直连，不依赖用户音源） ----

  /// 补全单曲 MV id：榜单/搜索里 mv 缺失或为 "0"（尤其网易搜索）时重新拉详情。
  /// 返回空串表示确实没有 MV。
  static Future<String> mvInfo(MusicSong song) async {
    if (!song.mvSupported) return '';
    if (song.hasMv) return song.mv;
    final r = await Api.i.call('music_mv_info', {
      'source': song.source, 'songInfo': song.toInfo(),
    });
    final mv = (r['mv'] ?? '').toString();
    return mv == '0' ? '' : mv;
  }

  /// MV 播放直链（酷狗/网易）。无 MV 或失败时抛异常。
  static Future<String> mvUrl({required String source, required String mvId}) async {
    final r = await Api.i.call('music_mv_url', {'source': source, 'mvId': mvId});
    if (r['ok'] != true || (r['url'] ?? '').toString().isEmpty) {
      throw Exception((r['error'] ?? '未找到 MV 播放链接').toString());
    }
    return r['url'].toString();
  }

  // ---- 音源管理 ----
  static Future<List<MusicSource>> sources() async {
    final r = await Api.i.call('music_source_list');
    final list = (r['list'] as List?) ?? [];
    return list.whereType<Map<String, dynamic>>().map(MusicSource.fromJson).toList();
  }

  static Future<Map<String, dynamic>> addSource(String script, {String url = '', bool enable = true, List<String> platforms = const []}) {
    return Api.i.call('music_source_add', {
      'source': script, 'url': url, 'enable': enable, 'sources': platforms,
    });
  }

  static Future<Map<String, dynamic>> importSourceUrl(String url, {bool enable = true}) {
    return Api.i.call('music_source_import_url', {'url': url, 'enable': enable});
  }

  static Future<Map<String, dynamic>> toggleSource(String id, bool enabled) {
    return Api.i.call('music_source_toggle', {'id': id, 'enabled': enabled});
  }

  static Future<Map<String, dynamic>> removeSource(String id) {
    return Api.i.call('music_source_remove', {'id': id});
  }

  static Future<String> sourceContent(String id) async {
    final r = await Api.i.call('music_source_content', {'id': id});
    return (r['source'] ?? '').toString();
  }
}

class MusicUrlResult {
  final String url;
  final String type;
  final String sourceName;
  MusicUrlResult({required this.url, required this.type, required this.sourceName});
}

/// LRC 单行
class LrcLine {
  final Duration time;
  final String text;
  const LrcLine({required this.time, required this.text});
}

/// LRC 解析（按时间升序）
List<LrcLine> parseLrc(String lrcText) {
  final lines = <LrcLine>[];
  final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final raw in lrcText.split('\n')) {
    for (final m in regex.allMatches(raw.trim())) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final msRaw = m.group(3)!;
      final ms = msRaw.length == 2 ? int.parse(msRaw) * 10 : int.parse(msRaw);
      final text = (m.group(4) ?? '').trim();
      lines.add(LrcLine(time: Duration(minutes: min, seconds: sec, milliseconds: ms), text: text));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
