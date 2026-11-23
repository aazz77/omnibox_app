// 内置央视频源（yspl）：通过 FFI 拿静态频道表 + 内嵌服务端口，
// 拼成与普通 M3U 频道同结构的 M3uChannel，播放地址指向本地 127.0.0.1:<port>/<slug>.m3u8。
// 服务由内核惰性启动（首次调用 iptv_yspl_port 时拉起），端口随机、仅监听回环。
import '../app_core.dart';
import 'm3u_parser.dart';

class BuiltinYspl {
  BuiltinYspl._();
  static final BuiltinYspl i = BuiltinYspl._();

  /// 拉取内置频道列表。任何一步失败都抛异常，由调用方 fail-fast 提示。
  Future<List<M3uChannel>> loadChannels() async {
    final portRes = await Api.i.call('iptv_yspl_port');
    if (portRes['ok'] != true) {
      throw Exception(portRes['error']?.toString() ?? '内置央视频服务启动失败');
    }
    final port = portRes['port'];
    if (port == null || port.toString().isEmpty) {
      throw Exception('内置央视频服务端口无效');
    }
    final chRes = await Api.i.call('iptv_yspl_channels');
    if (chRes['ok'] != true) {
      throw Exception(chRes['error']?.toString() ?? '内置央视频频道表读取失败');
    }
    final raw = (chRes['channels'] as List?) ?? [];
    final channels = <M3uChannel>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final slug = e['slug']?.toString() ?? '';
      if (slug.isEmpty) continue;
      final name = e['name']?.toString() ?? slug;
      final group = e['group']?.toString() ?? '央视频';
      channels.add(M3uChannel(
        name: name,
        url: 'http://127.0.0.1:$port/$slug.m3u8',
        group: group,
        logo: e['logo']?.toString() ?? '',
        id: e['tvgId']?.toString() ?? '',
      ));
    }
    if (channels.isEmpty) throw Exception('内置央视频频道表为空');
    return channels;
  }
}
