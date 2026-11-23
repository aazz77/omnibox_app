// 直播聚合 API：封装 ob_call('live_*')，对齐 live-server 的数据结构。
// 所有方法走同步 FFI + Dart isolate（ffi_client 已实现），无 HTTP / 无端口。
import '../app_core.dart';

class LiveSite {
  final String id;
  final String name;
  final bool searchable;
  final bool danmaku;
  LiveSite({required this.id, required this.name, this.searchable = true, this.danmaku = true});
  factory LiveSite.fromJson(Map<String, dynamic> j) => LiveSite(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        searchable: j['searchable'] as bool? ?? true,
        danmaku: j['danmaku'] as bool? ?? true,
      );
}

class LiveSearchItem {
  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final String avatar;
  final int online;
  final bool liveStatus;
  LiveSearchItem({
    required this.roomId, required this.title, required this.userName,
    this.cover = '', this.avatar = '', this.online = 0, this.liveStatus = false,
  });
  factory LiveSearchItem.fromJson(Map<String, dynamic> j) => LiveSearchItem(
        roomId: j['roomId']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        userName: j['userName']?.toString() ?? '',
        cover: j['cover']?.toString() ?? '',
        avatar: j['avatar']?.toString() ?? '',
        online: j['online'] as int? ?? 0,
        liveStatus: j['liveStatus'] as bool? ?? false,
      );
}

class LiveFollow {
  final String id;
  final String platform;
  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final int addTime;
  final bool top;
  final bool live;
  LiveFollow({
    required this.id, required this.platform, required this.roomId,
    this.title = '', this.cover = '', this.userName = '',
    this.addTime = 0, this.top = false, this.live = false,
  });
  factory LiveFollow.fromJson(Map<String, dynamic> j) => LiveFollow(
        id: j['id']?.toString() ?? '',
        platform: j['platform']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        cover: j['cover']?.toString() ?? '',
        userName: j['userName']?.toString() ?? '',
        addTime: j['addTime'] as int? ?? 0,
        top: j['top'] as bool? ?? false,
        live: j['live'] as bool? ?? false,
      );
}

class LiveLine {
  final String name;
  final String type; // hls / flv
  final String url;
  final Map<String, dynamic> headers;
  LiveLine({required this.name, required this.type, required this.url, this.headers = const {}});
  factory LiveLine.fromJson(Map<String, dynamic> j) => LiveLine(
        name: j['name']?.toString() ?? '线路',
        type: j['type']?.toString() ?? 'flv',
        url: j['url']?.toString() ?? '',
        headers: (j['headers'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class LiveQuality {
  final String name;
  final String key;
  final List<LiveLine> lines;
  LiveQuality({required this.name, required this.key, required this.lines});
  factory LiveQuality.fromJson(Map<String, dynamic> j) => LiveQuality(
        name: j['name']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        lines: ((j['lines'] as List?) ?? []).map((e) => LiveLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class LivePlayInfo {
  final List<LiveQuality> qualities;
  final bool danmaku;
  final String roomId;
  LivePlayInfo({required this.qualities, required this.danmaku, required this.roomId});
  factory LivePlayInfo.fromJson(Map<String, dynamic> j) => LivePlayInfo(
        qualities: ((j['qualities'] as List?) ?? []).map((e) => LiveQuality.fromJson(e as Map<String, dynamic>)).toList(),
        danmaku: j['danmaku'] as bool? ?? false,
        roomId: j['roomId']?.toString() ?? '',
      );
}

/// 统一弹幕消息（live-server DanmakuMessage）
class LiveDanmuMessage {
  final String type; // chat/online/error/info
  final String userName;
  final String message;
  final int color;
  final int online;
  LiveDanmuMessage({
    required this.type, this.userName = '', this.message = '',
    this.color = 0xffffff, this.online = 0,
  });
  factory LiveDanmuMessage.fromJson(Map<String, dynamic> j) => LiveDanmuMessage(
        type: j['type']?.toString() ?? 'chat',
        userName: j['userName']?.toString() ?? '',
        message: j['message']?.toString() ?? '',
        color: j['color'] as int? ?? 0xffffff,
        online: j['online'] as int? ?? 0,
      );
}

class LiveApi {
  LiveApi._();
  static final LiveApi i = LiveApi._();

  Future<List<LiveSite>> sites() async {
    final r = await Api.i.call('live_sites');
    return ((r['sites'] as List?) ?? []).map((e) => LiveSite.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 返回 (platform, roomId)；解析失败抛出 error
  Future<Map<String, String>> parseLink(String text) async {
    final r = await Api.i.call('live_parse', {'text': text});
    if (r['ok'] != true) throw Exception(r['error']?.toString() ?? '无法识别链接');
    return {'platform': r['platform']?.toString() ?? '', 'roomId': r['roomId']?.toString() ?? ''};
  }

  Future<Map<String, dynamic>> search(String platform, String kw, {int page = 1, bool anchor = false}) async {
    return Api.i.call('live_search', {'platform': platform, 'kw': kw, 'page': page, 'anchor': anchor});
  }

  Future<List<LiveSearchItem>> searchItems(String platform, String kw, {int page = 1, bool anchor = false}) async {
    final r = await search(platform, kw, page: page, anchor: anchor);
    return ((r['items'] as List?) ?? []).map((e) => LiveSearchItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> room(String platform, String roomId) =>
      Api.i.call('live_room', {'platform': platform, 'room': roomId});

  Future<LivePlayInfo?> play(String platform, String roomId) async {
    final r = await Api.i.call('live_play', {'platform': platform, 'room': roomId});
    if (r['ok'] != true) return null;
    return LivePlayInfo.fromJson(r);
  }

  Future<bool> liveStatus(String platform, String roomId) async {
    final r = await Api.i.call('live_status', {'platform': platform, 'room': roomId});
    return r['live'] as bool? ?? false;
  }

  Future<List<LiveFollow>> follows() async {
    final r = await Api.i.call('live_follows');
    return ((r['items'] as List?) ?? []).map((e) => LiveFollow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<bool> followAdd(String platform, String roomId, {String title = '', String cover = '', String userName = ''}) async {
    final r = await Api.i.call('live_follow_add', {
      'platform': platform, 'roomId': roomId,
      'title': title, 'cover': cover, 'userName': userName,
    });
    return r['ok'] == true;
  }

  Future<bool> followDel(String id) async {
    final r = await Api.i.call('live_follow_del', {'id': id});
    return r['ok'] == true;
  }

  Future<bool> followTop(String id, bool top) async {
    final r = await Api.i.call('live_follow_top', {'id': id, 'top': top});
    return r['ok'] == true;
  }

  Future<Map<String, dynamic>> settingsGet() => Api.i.call('live_settings_get');

  Future<bool> settingsSet(Map<String, dynamic> settings) async {
    final r = await Api.i.call('live_settings_set', settings);
    return r['ok'] == true;
  }

  // ---- 弹幕轮询 ----
  Future<bool> danmuStart(String platform, String roomId) async {
    final r = await Api.i.call('live_danmaku_start', {'platform': platform, 'room': roomId});
    return r['ok'] == true;
  }

  Future<List<LiveDanmuMessage>> danmuPoll(String platform, String roomId) async {
    final r = await Api.i.call('live_danmaku_poll', {'platform': platform, 'room': roomId});
    return ((r['messages'] as List?) ?? []).map((e) => LiveDanmuMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> danmuStop(String platform, String roomId) async {
    await Api.i.call('live_danmaku_stop', {'platform': platform, 'room': roomId});
  }
}
