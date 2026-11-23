// VLC 播放器封装（vlc_player 2.x，支持 Windows）。
// 用于 IPTV 直播流与点播备用内核：libVLC 对 HLS/TS/RTSP 的容错好于 mpv，
// 且自带去交错 + network-caching 缓冲协商。点播默认仍走 media_kit(libmpv)，
// 可在设置页切换为 VLC。
//
// vlc_player 在 Windows 构建时自动下载并打包 libVLC 运行时（libvlc.dll /
// libvlccore.dll / plugins/）；CI 构建后用 windows/scripts/strip_vlc_plugins.ps1
// 裁剪未使用的插件，把体积从 ~130MB 压到 ~33MB。
//
// 解码方式：与「设置」页的 VLC 硬解开关联动（直播 + 点播共用）。
//   :avcodec-hw=any  —— VLC 自动选最佳硬解（Windows 上 D3D11VA/DXVA2）
//   :avcodec-hw=none —— 强制软解，兼容性更好但 CPU 占用高。
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vlc_player/vlc_player.dart';

import '../app_core.dart';
import '../settings.dart';
import 'danmu_overlay.dart';

/// VLC 后端控制器：持有当前 VlcPlayerController，切流时销毁旧的、新建。
/// mixin ChangeNotifier：controller 被替换或播放状态变化时 notifyListeners，
/// 视图层用 AnimatedBuilder 监听后重建。
class VlcController with ChangeNotifier {
  VlcPlayerController? _controller;
  bool _disposed = false;

  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  final ValueNotifier<double> volume = ValueNotifier<double>(100.0);

  /// 控制条用：当前位置 / 总时长（ValueNotifier 便于 Slider 高频刷新）。
  final ValueNotifier<Duration> positionVN = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> durationVN = ValueNotifier<Duration>(Duration.zero);

  /// 播放位置流（Duration），供弹幕层按视频时间排程。
  /// VlcPlayerValue.position 不可直接 stream，这里用广播流转发变化。
  final StreamController<Duration> _positionCtrl = StreamController<Duration>.broadcast();
  Stream<Duration> get position => _positionCtrl.stream;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;

  VlcPlayerController? get controller => _controller;

  /// 是否走硬件解码（构造时快照设置，切换需重建控制器/播放页）
  final bool hardwareDecode;

  VlcController({bool? hardwareDecode})
      : hardwareDecode = hardwareDecode ?? AppSettings.i.vlcHwdec.value;

  /// 打开一个网络流或本地文件。
  /// [headers] 仅点播需要（UA/Referer 鉴权），映射为 VLC 的 http 选项。
  /// IPTV 参数：
  ///   :network-caching=1500 —— 默认 1000ms 抖动易卡顿，1500ms 是平衡值
  ///   :avcodec-hw=any/none  —— 硬软解
  ///   :no-video-title-show  —— 去掉 VLC 自带的频道名 OSD（UI 已有）
  Future<void> open(String pathOrUrl, {Map<String, dynamic>? headers}) async {
    if (_disposed) return;
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _controller = null;
    playing.value = false;
    buffering.value = false;
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    positionVN.value = Duration.zero;
    durationVN.value = Duration.zero;
    _positionCtrl.add(Duration.zero);

    Uri uri;
    try {
      uri = Uri.parse(pathOrUrl);
      // Uri.parse('C:\\a.m3u8') 会把 C 当 scheme；含盘符的按文件路径处理
      if (uri.scheme.length == 1) uri = Uri.file(pathOrUrl);
    } catch (_) {
      uri = Uri.file(pathOrUrl);
    }

    final mediaOptions = <String>[
      ':network-caching=1500',
      ':no-video-title-show',
      if (hardwareDecode) ':avcodec-hw=any' else ':avcodec-hw=none',
    ];
    // 点播鉴权头：VLC 只认这两个标准选项；其它头（如 Origin）无对应 option。
    headers?.forEach((k, v) {
      final key = k.toString().toLowerCase();
      if (key == 'user-agent') {
        mediaOptions.add(':http-user-agent=$v');
      } else if (key == 'referer') {
        mediaOptions.add(':http-referer=$v');
      }
    });

    final next = VlcPlayerController(
      mediaSource: VlcMediaSource(
        uri: uri,
        mediaOptions: mediaOptions,
      ),
      autoPlay: true,
    );
    _controller = next;
    next.addListener(_onChanged);
    _onChanged();
    notifyListeners();
  }

  void _onChanged() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final p = v.state == VlcPlaybackState.playing;
    final b = v.state == VlcPlaybackState.buffering ||
        v.state == VlcPlaybackState.opening;
    if (p != playing.value) {
      playing.value = p;
      notifyListeners();
    }
    if (b != buffering.value) {
      buffering.value = b;
      notifyListeners();
    }
    // position 变化转发给弹幕层 + 控制条
    if (v.position != _lastPosition) {
      _lastPosition = v.position;
      positionVN.value = v.position;
      _positionCtrl.add(v.position);
    }
    // duration 变化（点播加载完成后从 0 变为实际时长）
    if (v.duration != _lastDuration) {
      _lastDuration = v.duration;
      durationVN.value = v.duration;
    }
    // VLC 原生音量 0-200，归一化到 0-100
    final vol = (v.volume / 2).clamp(0.0, 100.0);
    if (vol != volume.value) volume.value = vol;
  }

  Future<void> playOrPause() async {
    final c = _controller;
    if (c == null || _disposed) return;
    try {
      if (c.value.state == VlcPlaybackState.playing) {
        await c.pause();
      } else {
        await c.play();
      }
    } on VlcPlayerException {
      // 播放指令失败（如尚未 attach），忽略，UI 状态以下一次 _onChanged 为准
    }
  }

  Future<void> setVolume(double v) async {
    final c = _controller;
    if (c == null || _disposed) return;
    final clamped = v.clamp(0.0, 100.0);
    volume.value = clamped;
    try {
      await c.setVolume((clamped * 2).round());
    } on VlcPlayerException {
      // 忽略
    }
  }

  /// 跳转到指定位置（进度条拖动）。拖动时先乐观更新 UI，VLC 回调会校正。
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null || _disposed) return;
    positionVN.value = position;
    try {
      await c.seekTo(position);
    } on VlcPlayerException {
      // 忽略：下一次 position 回调会校正回真实位置
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _controller = null;
    playing.dispose();
    buffering.dispose();
    volume.dispose();
    positionVN.dispose();
    durationVN.dispose();
    _positionCtrl.close();
    super.dispose();
  }
}

/// VLC 视频渲染组件。用 AnimatedBuilder 监听 backend 的 ChangeNotifier，
/// 在 controller 被替换（切流）时重建 VlcPlayer。
class VlcVideoView extends StatelessWidget {
  final VlcController backend;
  final Color fill;
  final BoxFit fit;
  /// 透传给内部 VlcPlayer 的 key：分屏↔全屏切换时让 State 移动而非重建，
  /// 避免 Windows texture-backed 渲染表面丢失导致全屏黑屏。
  final Key? playerKey;

  const VlcVideoView({
    required this.backend,
    this.fill = Colors.black,
    this.fit = BoxFit.contain,
    this.playerKey,
    Key? key,
  }) : super(key: key);

  VlcVideoFit _mapFit(BoxFit f) {
    switch (f) {
      case BoxFit.fill:
        return VlcVideoFit.fill;
      case BoxFit.cover:
        return VlcVideoFit.cover;
      default:
        return VlcVideoFit.contain;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: backend,
      builder: (context, _) {
        final controller = backend.controller;
        if (controller == null) {
          return ColoredBox(color: fill, child: const SizedBox.expand());
        }
        return ColoredBox(
          color: fill,
          child: SizedBox.expand(
            child: VlcPlayer(
              key: playerKey,
              controller: controller,
              backgroundColor: fill,
              fit: _mapFit(fit),
            ),
          ),
        );
      },
    );
  }
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 点播 VLC 播放器：URL + 鉴权头 + 弹幕层 + 控制条（进度/播放/音量/全屏）。
/// 硬解开关变化时用 ValueKey 强制重建内层，确保 :avcodec-hw=any/none 生效。
class VlcVodPlayer extends StatelessWidget {
  final String url;
  final Map<String, dynamic> headers;
  final List<DanmuItem> danmuItems;
  /// 由 detail 页持有：全屏切换时让 VlcPlayer 的 State 移动而非重建（防黑屏）。
  final Key? playerKey;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const VlcVodPlayer({
    required this.url,
    required this.headers,
    required this.onToggleFullscreen,
    this.danmuItems = const [],
    this.playerKey,
    this.isFullscreen = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.i.vlcHwdec,
      builder: (context, hw, _) => _VlcVodPlayerInner(
        key: ValueKey<bool>(hw),
        url: url,
        headers: headers,
        danmuItems: danmuItems,
        hardwareDecode: hw,
        playerKey: playerKey,
        isFullscreen: isFullscreen,
        onToggleFullscreen: onToggleFullscreen,
      ),
    );
  }
}

class _VlcVodPlayerInner extends StatefulWidget {
  final String url;
  final Map<String, dynamic> headers;
  final List<DanmuItem> danmuItems;
  final bool hardwareDecode;
  final Key? playerKey;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  const _VlcVodPlayerInner({
    required this.url,
    required this.headers,
    required this.danmuItems,
    required this.hardwareDecode,
    required this.playerKey,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    Key? key,
  }) : super(key: key);

  @override
  State<_VlcVodPlayerInner> createState() => _VlcVodPlayerInnerState();
}

class _VlcVodPlayerInnerState extends State<_VlcVodPlayerInner> {
  late final VlcController _vlc;

  @override
  void initState() {
    super.initState();
    _vlc = VlcController(hardwareDecode: widget.hardwareDecode);
    _vlc.open(widget.url, headers: widget.headers);
  }

  @override
  void didUpdateWidget(_VlcVodPlayerInner old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _vlc.open(widget.url, headers: widget.headers);
    }
  }

  @override
  void dispose() {
    _vlc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          VlcVideoView(backend: _vlc, playerKey: widget.playerKey),
          if (widget.danmuItems.isNotEmpty)
            Positioned.fill(
              child: DanmuOverlay(
                positionStream: _vlc.position,
                items: widget.danmuItems,
              ),
            ),
          // VLC 插件本身不带 UI，这里补完整控制条（进度/播放/音量/全屏）。
          _VlcControlBar(
            backend: _vlc,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
        ],
      ),
    );
  }
}

/// VLC 点播控制条：播放/暂停 + 拖动进度 + 时间 + 音量 + 全屏。
class _VlcControlBar extends StatelessWidget {
  final VlcController backend;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const _VlcControlBar({
    required this.backend,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: const Color(0x88000000),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: backend.playing,
              builder: (context, playing, _) => IconButton(
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: backend.playOrPause,
              ),
            ),
            // 进度条：监听位置与时长，拖动调用 seek
            Expanded(
              child: ValueListenableBuilder<Duration>(
                valueListenable: backend.durationVN,
                builder: (context, duration, _) => ValueListenableBuilder<Duration>(
                  valueListenable: backend.positionVN,
                  builder: (context, position, _) {
                    final maxMs = duration.inMilliseconds.toDouble();
                    final posMs = maxMs > 0
                        ? position.inMilliseconds.clamp(0, maxMs).toDouble()
                        : 0.0;
                    return Row(
                      children: [
                        Text(_fmtDuration(position),
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: posMs,
                            min: 0,
                            max: maxMs > 0 ? maxMs : 1,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white54,
                            onChanged: maxMs > 0
                                ? (v) => backend.seek(Duration(milliseconds: v.round()))
                                : null,
                          ),
                        ),
                        Text(_fmtDuration(duration),
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    );
                  },
                ),
              ),
            ),
            // 音量
            ValueListenableBuilder<double>(
              valueListenable: backend.volume,
              builder: (context, vol, _) => SizedBox(
                width: 96,
                child: Slider(
                  value: vol,
                  min: 0,
                  max: 100,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white54,
                  onChanged: (v) => backend.setVolume(v),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              tooltip: isFullscreen ? '退出全屏' : '全屏',
              onPressed: onToggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}
