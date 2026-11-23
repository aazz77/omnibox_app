// 轻量应用设置：dart:io + JSON 持久化到 <dataDir>/settings.json，零新增依赖。
// hwdec / danmu 用 ValueNotifier 广播，播放器与弹幕层监听后即时生效。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 解码方式选项（value 直接传给 mpv 的 --hwdec）
class HwdecOption {
  final String value;
  final String label;
  final String desc;
  const HwdecOption(this.value, this.label, this.desc);
}

/// 音乐音质偏好选项（对齐 lx-server 的四档 + 智能降级）
/// value 是传给内核 / 音源脚本 type 参数的值。
class MusicQualityOption {
  final String value;
  final String label;
  final String desc;
  const MusicQualityOption(this.value, this.label, this.desc);
}

/// 弹幕渲染设置（语义对齐 danmu-anywhere 插件的 DanmuSettings）
/// 不可变对象，改动用 copyWith，通过 ValueNotifier 广播让弹幕层实时重排。
class DanmuConfig {
  final bool open;        // 是否显示弹幕
  final int lines;        // 轨道行数 1~30
  final double speed;     // 滚动速度因子，越大越慢（0.5~5.0）
  final double size;      // 字号缩放 0.4~2.4
  final double alpha;     // 透明度 0.1~1.0
  final int spacing;      // 行间距 px 0~32
  final int top;          // 顶部边距 px 0~300
  final bool randomColor; // 随机颜色（忽略弹幕自带颜色）
  final String apiBase;   // 弹幕 API 地址，空串用内置默认镜像

  const DanmuConfig({
    this.open = true,
    this.lines = 3,
    this.speed = 1.5,
    this.size = 0.7,
    this.alpha = 0.9,
    this.spacing = 8,
    this.top = 20,
    this.randomColor = false,
    this.apiBase = '',
  });

  static const DanmuConfig defaults = DanmuConfig();

  DanmuConfig copyWith({
    bool? open,
    int? lines,
    double? speed,
    double? size,
    double? alpha,
    int? spacing,
    int? top,
    bool? randomColor,
    String? apiBase,
  }) {
    return DanmuConfig(
      open: open ?? this.open,
      lines: lines ?? this.lines,
      speed: speed ?? this.speed,
      size: size ?? this.size,
      alpha: alpha ?? this.alpha,
      spacing: spacing ?? this.spacing,
      top: top ?? this.top,
      randomColor: randomColor ?? this.randomColor,
      apiBase: apiBase ?? this.apiBase,
    );
  }

  Map<String, dynamic> toJson() => {
        'open': open,
        'lines': lines,
        'speed': speed,
        'size': size,
        'alpha': alpha,
        'spacing': spacing,
        'top': top,
        'randomColor': randomColor,
        'apiBase': apiBase,
      };

  factory DanmuConfig.fromJson(Map<dynamic, dynamic> m) {
    return DanmuConfig(
      open: (m['open'] as bool?) ?? true,
      lines: _clampInt(m['lines'], 1, 30, 3),
      speed: _clampDouble(m['speed'], 0.5, 5.0, 1.5),
      size: _clampDouble(m['size'], 0.4, 2.4, 0.7),
      alpha: _clampDouble(m['alpha'], 0.1, 1.0, 0.9),
      spacing: _clampInt(m['spacing'], 0, 32, 8),
      top: _clampInt(m['top'], 0, 300, 20),
      randomColor: (m['randomColor'] as bool?) ?? false,
      apiBase: (m['apiBase'] as String?) ?? '',
    );
  }

  static int _clampInt(dynamic v, int min, int max, int def) {
    if (v == null) return def;
    final n = v is num ? v.round() : int.tryParse(v.toString()) ?? def;
    return n < min ? min : (n > max ? max : n);
  }

  static double _clampDouble(dynamic v, double min, double max, double def) {
    if (v == null) return def;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? def;
    return n < min ? min : (n > max ? max : n);
  }
}

/// 直播弹幕设置（对齐 live-server 的 DanmakuSettings），独立于点播弹幕。
/// 由直播播放页的实时弹幕层监听 ValueNotifier 即时生效，并持久化到内核 silm.json。
class LiveDanmuConfig {
  final bool enabled;
  final int fontSize;      // 字号 px
  final int area;          // 显示区域占画面高度百分比
  final int lineGap;       // 行间距 px
  final int itemGap;       // 同轨道水平最小间距 px
  final double duration;   // 横穿屏幕秒数，越小越快
  final String colorMode;  // platform/custom/white/rainbow
  final String color;      // custom 模式的颜色 #RRGGBB
  final double opacity;    // 不透明度 0.2~1
  final bool bold;
  final bool stroke;
  final bool showUser;

  const LiveDanmuConfig({
    this.enabled = true,
    this.fontSize = 22,
    this.area = 60,
    this.lineGap = 10,
    this.itemGap = 64,
    this.duration = 9,
    this.colorMode = 'platform',
    this.color = '#ffffff',
    this.opacity = 1,
    this.bold = true,
    this.stroke = true,
    this.showUser = true,
  });

  static const LiveDanmuConfig defaults = LiveDanmuConfig();

  LiveDanmuConfig copyWith({
    bool? enabled, int? fontSize, int? area, int? lineGap, int? itemGap,
    double? duration, String? colorMode, String? color, double? opacity,
    bool? bold, bool? stroke, bool? showUser,
  }) {
    return LiveDanmuConfig(
      enabled: enabled ?? this.enabled,
      fontSize: fontSize ?? this.fontSize,
      area: area ?? this.area,
      lineGap: lineGap ?? this.lineGap,
      itemGap: itemGap ?? this.itemGap,
      duration: duration ?? this.duration,
      colorMode: colorMode ?? this.colorMode,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      bold: bold ?? this.bold,
      stroke: stroke ?? this.stroke,
      showUser: showUser ?? this.showUser,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled, 'fontSize': fontSize, 'area': area,
        'lineGap': lineGap, 'itemGap': itemGap, 'duration': duration,
        'colorMode': colorMode, 'color': color, 'opacity': opacity,
        'bold': bold, 'stroke': stroke, 'showUser': showUser,
      };

  factory LiveDanmuConfig.fromJson(Map<dynamic, dynamic> m) {
    return LiveDanmuConfig(
      enabled: (m['enabled'] as bool?) ?? true,
      fontSize: ((m['fontSize'] as num?) ?? 22).round().clamp(12, 48),
      area: ((m['area'] as num?) ?? 60).round().clamp(20, 100),
      lineGap: ((m['lineGap'] as num?) ?? 10).round().clamp(0, 40),
      itemGap: ((m['itemGap'] as num?) ?? 64).round().clamp(0, 300),
      duration: ((m['duration'] as num?) ?? 9).toDouble().clamp(2, 20),
      colorMode: (m['colorMode'] as String?) ?? 'platform',
      color: (m['color'] as String?) ?? '#ffffff',
      opacity: ((m['opacity'] as num?) ?? 1).toDouble().clamp(0.2, 1),
      bold: (m['bold'] as bool?) ?? true,
      stroke: (m['stroke'] as bool?) ?? true,
      showUser: (m['showUser'] as bool?) ?? true,
    );
  }
}

class AppSettings {
  AppSettings._();
  static final AppSettings i = AppSettings._();

  static const String defaultHwdec = 'auto-safe';
  static const List<HwdecOption> hwdecOptions = [
    HwdecOption('no', '软件解码', 'CPU 软解，兼容性最好'),
    HwdecOption('auto-safe', '硬件解码', '自动硬解，失败时安全回退（推荐）'),
    HwdecOption('d3d11va', '强制硬解', 'Windows D3D11VA，部分机器不支持'),
  ];

  /// 点播播放器内核：'mpv'（media_kit/libmpv）或 'vlc'（libVLC）
  static const String defaultVodPlayer = 'mpv';
  static const List<HwdecOption> vodPlayerOptions = [
    HwdecOption('mpv', 'mpv', 'libmpv，点播默认，弹幕同步成熟'),
    HwdecOption('vlc', 'VLC', 'libVLC，对 m3u8/TS 等流容错更好'),
  ];

  /// iptv（M3U 直播，VLC 内核）硬解开关：即原来的「直播解码」，现独立为 iptv 解码。
  static const bool defaultIptvHwdec = true;
  final ValueNotifier<bool> iptvHwdec = ValueNotifier<bool>(defaultIptvHwdec);

  /// 直播（6 平台聚合）播放器内核：'mpv' 或 'vlc'，独立于点播/iptv。
  static const String defaultLivePlayer = 'mpv';
  final ValueNotifier<String> livePlayer = ValueNotifier<String>(defaultLivePlayer);

  /// 直播 mpv 解码方式（value 传给 --hwdec），独立于点播。
  static const String defaultLiveHwdec = 'auto-safe';
  final ValueNotifier<String> liveHwdec = ValueNotifier<String>(defaultLiveHwdec);

  /// 直播默认画质偏好：highest/720p/lowest。播放时按可用档位自动选择。
  static const String defaultLiveQuality = 'highest';
  static const List<HwdecOption> liveQualityOptions = [
    HwdecOption('highest', '最高画质', '自动选择清晰度最高的档位'),
    HwdecOption('720p', '720P 优先', '优先 720P，无则取最接近'),
    HwdecOption('lowest', '最低画质', '省流量，加载更快'),
  ];
  final ValueNotifier<String> liveQuality = ValueNotifier<String>(defaultLiveQuality);

  /// 直播弹幕设置（实时弹幕层监听），独立于点播弹幕。
  final ValueNotifier<LiveDanmuConfig> liveDanmu =
      ValueNotifier<LiveDanmuConfig>(LiveDanmuConfig.defaults);

  /// 当前点播解码方式（mpv 播放器监听此值，value 传给 --hwdec）
  final ValueNotifier<String> hwdec = ValueNotifier<String>(defaultHwdec);

  /// 点播内核（切换即重建当前播放页的播放器）
  final ValueNotifier<String> vodPlayer = ValueNotifier<String>(defaultVodPlayer);

  /// VLC 是否硬件解码（直播 + 点播 VLC 共用）；true=any，false=none。
  /// 进入播放页时快照，切换需重建播放器。
  final ValueNotifier<bool> vlcHwdec = ValueNotifier<bool>(true);

  /// 音乐音质偏好（对齐 lx-server 的 preferredQuality，默认高品质 320k）。
  /// 播放时按歌曲实际支持的 types 从该偏好向下智能降级。
  static const String defaultMusicQuality = '320k';
  static const List<MusicQualityOption> musicQualityOptions = [
    MusicQualityOption('128k', '标准 128K', '流畅，体积最小'),
    MusicQualityOption('320k', '高品质 320K', '推荐，音质与体积平衡'),
    MusicQualityOption('flac', '无损 FLAC', 'CD 级无损'),
    MusicQualityOption('flac24bit', 'Hi-Res', '24bit 高解析，体积最大'),
  ];
  final ValueNotifier<String> preferredQuality = ValueNotifier<String>(defaultMusicQuality);

  /// 弹幕设置（弹幕层监听此值）
  final ValueNotifier<DanmuConfig> danmu = ValueNotifier<DanmuConfig>(DanmuConfig.defaults);

  String _filePath = '';

  /// main() 拿到 dataDir 后调用
  void init(String dataDir) {
    _filePath = '${dataDir}${Platform.pathSeparator}settings.json';
    _load();
  }

  void _load() {
    if (_filePath.isEmpty) return;
    try {
      final f = File(_filePath);
      if (!f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync());
      if (m is Map) {
        final v = m['hwdec']?.toString();
        if (v != null && hwdecOptions.any((o) => o.value == v)) {
          hwdec.value = v;
        }
        final vp = m['vodPlayer']?.toString();
        if (vp != null && vodPlayerOptions.any((o) => o.value == vp)) {
          vodPlayer.value = vp;
        }
        final pq = m['preferredQuality']?.toString();
        if (pq != null && musicQualityOptions.any((o) => o.value == pq)) {
          preferredQuality.value = pq;
        }
        final d = m['danmu'];
        if (d is Map) danmu.value = DanmuConfig.fromJson(d);
        vlcHwdec.value = (m['vlcHwdec'] as bool?) ?? true;

        // 直播 / iptv 设置
        iptvHwdec.value = (m['iptvHwdec'] as bool?) ?? true;
        final lp = m['livePlayer']?.toString();
        if (lp != null && (lp == 'mpv' || lp == 'vlc')) livePlayer.value = lp;
        final lh = m['liveHwdec']?.toString();
        if (lh != null && hwdecOptions.any((o) => o.value == lh)) liveHwdec.value = lh;
        final lq = m['liveQuality']?.toString();
        if (lq != null && liveQualityOptions.any((o) => o.value == lq)) liveQuality.value = lq;
        final ld = m['liveDanmu'];
        if (ld is Map) liveDanmu.value = LiveDanmuConfig.fromJson(ld);
      }
    } catch (_) {
      // 配置损坏则保留默认值
    }
  }

  void setHwdec(String value) {
    if (!hwdecOptions.any((o) => o.value == value)) return;
    hwdec.value = value;
    _save();
  }

  void setVodPlayer(String value) {
    if (!vodPlayerOptions.any((o) => o.value == value)) return;
    vodPlayer.value = value;
    _save();
  }

  void setDanmu(DanmuConfig config) {
    danmu.value = config; // 触发弹幕层即时重排
    _save();
  }

  void setVlcHwdec(bool value) {
    vlcHwdec.value = value;
    _save();
  }

  void setPreferredQuality(String value) {
    if (!musicQualityOptions.any((o) => o.value == value)) return;
    preferredQuality.value = value; // 广播，播放器监听后按新偏好重解当前曲目
    _save();
  }

  void setIptvHwdec(bool value) {
    iptvHwdec.value = value;
    _save();
  }

  void setLivePlayer(String value) {
    if (value != 'mpv' && value != 'vlc') return;
    livePlayer.value = value;
    _save();
  }

  void setLiveHwdec(String value) {
    if (!hwdecOptions.any((o) => o.value == value)) return;
    liveHwdec.value = value;
    _save();
  }

  void setLiveQuality(String value) {
    if (!liveQualityOptions.any((o) => o.value == value)) return;
    liveQuality.value = value;
    _save();
  }

  void setLiveDanmu(LiveDanmuConfig config) {
    liveDanmu.value = config;
    _save();
  }

  void _save() {
    if (_filePath.isEmpty) return;
    try {
      final f = File(_filePath);
      final dir = f.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({
        'hwdec': hwdec.value,
        'vodPlayer': vodPlayer.value,
        'vlcHwdec': vlcHwdec.value,
        'preferredQuality': preferredQuality.value,
        'danmu': danmu.value.toJson(),
        'iptvHwdec': iptvHwdec.value,
        'livePlayer': livePlayer.value,
        'liveHwdec': liveHwdec.value,
        'liveQuality': liveQuality.value,
        'liveDanmu': liveDanmu.value.toJson(),
      }));
    } catch (_) {
      // 写失败不影响本次运行
    }
  }
}
