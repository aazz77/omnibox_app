// media_kit 播放器封装（基于 libmpv）。
// 解码方式由「设置」页控制（AppSettings.i.hwdec）。
// media_kit 不提供 Player.setProperty；hwdec 是 VideoControllerConfiguration 的
// 原生启动参数（--hwdec），构造时下发。因此切换解码方式会重建 Player + VideoController
// 并重新加载当前剧集，确保新模式真正生效。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../app_core.dart';
import '../settings.dart';
import 'danmu_overlay.dart';

/// 用 media_kit 播放一个 URL，可携带自定义 HTTP header（UA/Referer/Origin）。
/// danmuItems 为当前集的弹幕列表（可为空），非空时在视频上叠加弹幕层。
class MpvPlayer extends StatefulWidget {
  final String url;
  final Map<String, dynamic> headers;
  final List<DanmuItem> danmuItems;
  final VoidCallback? onError;
  MpvPlayer({required this.url, required this.headers, this.danmuItems = const [], this.onError, Key? key}) : super(key: key);

  @override
  State<MpvPlayer> createState() => _MpvPlayerState();
}

class _MpvPlayerState extends State<MpvPlayer> {
  late Player _player;
  late VideoController _controller;
  String? _error;

  // 当前播放源，供切换解码方式后重新加载
  String? _url;
  Map<String, dynamic> _headers = {};
  final ValueNotifier<String> _hwdec = AppSettings.i.hwdec;

  @override
  void initState() {
    super.initState();
    _create();
    _hwdec.addListener(_onHwdecChanged);
    _open(widget.url, widget.headers);
  }

  /// 按当前 hwdec 设置创建 Player 与 VideoController
  void _create() {
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(hwdec: _hwdec.value),
    );
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
      widget.onError?.call();
    });
  }

  @override
  void didUpdateWidget(MpvPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() => _error = null);
      _open(widget.url, widget.headers);
    }
  }

  /// 设置页切换硬软解：hwdec 是原生启动参数，重建播放器并重新加载当前源。
  Future<void> _onHwdecChanged() async {
    final u = _url;
    if (u == null) return;
    await _player.dispose();
    if (!mounted) return;
    _create();
    setState(() {}); // 让 Video widget 指向新 controller
    _open(u, _headers);
  }

  void _open(String url, Map<String, dynamic> headers) {
    _url = url;
    _headers = Map<String, dynamic>.from(headers);
    final h = <String, String>{};
    headers.forEach((k, v) => h[k.toString()] = v.toString());
    final media = Media(url, httpHeaders: h);
    _player.open(media, play: true).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
      widget.onError?.call();
    });
  }

  @override
  void dispose() {
    _hwdec.removeListener(_onHwdecChanged);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.play_circle_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('播放失败: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() => _error = null);
                final u = _url;
                if (u != null) _open(u, _headers);
              },
              child: const Text('重试'),
            ),
          ]),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: Video(
        controller: _controller,
        // 弹幕层放进 controls，而不是叠在 Video 外层。
        // 原因：media_kit 的全屏按钮会 Navigator.push 一个只含 Video 的新路由，
        // 但新路由会复用同一个 controls builder。把弹幕作为 controls 的一部分，
        // 弹幕就会跟随 Video 一起进入全屏（否则全屏后外层的弹幕层不在新路由里而丢失）。
        controls: (state) => Stack(
          children: [
            AdaptiveVideoControls(state),
            if (widget.danmuItems.isNotEmpty)
              Positioned.fill(
                child: DanmuOverlay(
                  player: state.widget.controller.player,
                  items: widget.danmuItems,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
