// 直播播放页：全屏 push（无左侧导航栏）。
// 内核按 AppSettings.livePlayer 选 mpv(media_kit) / VLC；解码用 liveHwdec / vlcHwdec。
// 数据来自 LiveApi.play（原始流 URL + 请求头，播放器直连），弹幕走 LiveApi 轮询 + LiveDanmuOverlay。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../live/live_api.dart';
import '../../live/live_danmu_overlay.dart';
import '../../player/vlc_player.dart';
import '../../settings.dart';

/// 全屏打开直播播放页
void openLivePlayer(BuildContext context, {
  required String platform, required String roomId,
  String title = '', String userName = '',
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LivePlayerHost(platform: platform, roomId: roomId, title: title, userName: userName),
  ));
}

class LivePlayerHost extends StatefulWidget {
  final String platform;
  final String roomId;
  final String title;
  final String userName;
  const LivePlayerHost({required this.platform, required this.roomId, this.title = '', this.userName = '', Key? key}) : super(key: key);
  @override
  State<LivePlayerHost> createState() => _LivePlayerHostState();
}

class _LivePlayerHostState extends State<LivePlayerHost> {
  LivePlayInfo? _info;
  int _qi = 0;   // 清晰度索引
  int _li = 0;   // 线路索引
  bool _loading = true;
  String? _error;
  bool _showControls = true;

  // mpv
  Player? _player;
  VideoController? _controller;
  // VLC
  VlcController? _vlc;
  // 弹幕
  final ValueNotifier<List<LiveDanmuMessage>> _danmuIncoming = ValueNotifier([]);
  Timer? _danmuTimer;
  bool _danmuOn = true;
  bool _followed = false;

  LiveLine? get _line {
    final info = _info;
    if (info == null || info.qualities.isEmpty) return null;
    final q = info.qualities[_qi.clamp(0, info.qualities.length - 1)];
    if (q.lines.isEmpty) return null;
    return q.lines[_li.clamp(0, q.lines.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _danmuTimer?.cancel();
    _player?.dispose();
    _vlc?.dispose();
    _danmuIncoming.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final info = await LiveApi.i.play(widget.platform, widget.roomId);
    if (!mounted) return;
    if (info == null || info.qualities.isEmpty) {
      setState(() { _loading = false; _error = '未获取到播放地址（房间可能未开播）'; });
      return;
    }
    // 按画质偏好选默认档位
    final pref = AppSettings.i.liveQuality.value;
    int qi = 0;
    if (pref == 'lowest') {
      qi = info.qualities.length - 1;
    } else if (pref == '720p') {
      final idx = info.qualities.indexWhere((q) => q.key.contains('720') || q.name.contains('720'));
      if (idx >= 0) qi = idx;
    }
    setState(() { _info = info; _qi = qi; _li = 0; _loading = false; });
    await _openStream();
    if (info.danmaku) _startDanmu();
  }

  Future<void> _openStream() async {
    final line = _line;
    if (line == null || line.url.isEmpty) return;
    // 先释放旧播放器
    await _player?.dispose();
    _player = null;
    _controller = null;
    _vlc?.dispose();
    _vlc = null;

    if (AppSettings.i.livePlayer.value == 'vlc') {
      _vlc = VlcController(hardwareDecode: AppSettings.i.vlcHwdec.value);
      await _vlc!.open(line.url, headers: line.headers);
    } else {
      final p = Player();
      final h = <String, String>{};
      line.headers.forEach((k, v) => h[k.toString()] = v.toString());
      _player = p;
      _controller = VideoController(p, configuration: VideoControllerConfiguration(hwdec: AppSettings.i.liveHwdec.value));
      await p.open(Media(line.url, httpHeaders: h), play: true);
    }
    if (mounted) setState(() {});
  }

  void _startDanmu() {
    _danmuTimer?.cancel();
    _danmuOn = AppSettings.i.danmu.value.open;
    if (!_danmuOn) return;
    LiveApi.i.danmuStart(widget.platform, widget.roomId);
    _danmuTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      final msgs = await LiveApi.i.danmuPoll(widget.platform, widget.roomId);
      if (msgs.isNotEmpty && mounted) _danmuIncoming.value = [..._danmuIncoming.value, ...msgs];
    });
  }

  void _toggleDanmu() {
    setState(() => _danmuOn = !_danmuOn);
    if (_danmuOn) {
      _startDanmu();
    } else {
      _danmuTimer?.cancel();
      LiveApi.i.danmuStop(widget.platform, widget.roomId);
    }
  }

  Future<void> _addFollow() async {
    final ok = await LiveApi.i.followAdd(widget.platform, widget.roomId, title: widget.title, userName: widget.userName);
    if (!mounted) return;
    setState(() => _followed = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已加入关注' : '关注失败')));
  }

  void _switchQuality(int i) {
    if (i == _qi) return;
    setState(() { _qi = i; _li = 0; _loading = true; });
    _openStream().then((_) => setState(() => _loading = false));
  }

  void _switchLine(int i) {
    if (i == _li) return;
    setState(() { _li = i; _loading = true; });
    _openStream().then((_) => setState(() => _loading = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(children: [
          // 视频层
          Positioned.fill(child: _buildVideo()),
          // 弹幕层（叠在视频上，控件显隐不影响它）
          if (_danmuOn)
            Positioned.fill(child: LiveDanmuOverlay(incoming: _danmuIncoming)),
          // 顶部返回栏
          if (_showControls)
            Positioned(top: 0, left: 0, right: 0, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent])),
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 24),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title.isEmpty ? widget.roomId : widget.title, style: const TextStyle(color: Colors.white, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(widget.userName, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1),
                ])),
                IconButton(icon: Icon(_danmuOn ? Icons.subtitles : Icons.subtitles_off, color: Colors.white), tooltip: '弹幕开关', onPressed: _toggleDanmu),
                IconButton(icon: Icon(_followed ? Icons.star : Icons.star_border, color: Colors.white), tooltip: '关注', onPressed: _addFollow),
              ]),
            )),
          // 底部：清晰度 / 线路
          if (_showControls && _info != null)
            Positioned(bottom: 0, left: 0, right: 0, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)])),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                _buildLineRow('画质', _info!.qualities.map((q) => q.name).toList(), _qi, _switchQuality),
                const SizedBox(height: 8),
                _buildLineRow('线路', (_line != null)
                    ? _info!.qualities[_qi.clamp(0, _info!.qualities.length - 1)].lines.map((l) => l.name).toList() : const [], _li, _switchLine),
              ]),
            )),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) Center(child: Container(
            padding: const EdgeInsets.all(20), color: Colors.black54,
            child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          )),
        ]),
      ),
    );
  }

  Widget _buildLineRow(String label, List<String> names, int selected, void Function(int) onPick) {
    return Row(children: [
      SizedBox(width: 40, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (int i = 0; i < names.length; i++)
          Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(names[i]), selected: i == selected,
            onSelected: (_) => onPick(i),
            selectedColor: Colors.indigo,
          )),
      ]))),
    ]);
  }

  Widget _buildVideo() {
    if (AppSettings.i.livePlayer.value == 'vlc') {
      final v = _vlc;
      if (v == null) return const Center(child: Icon(Icons.live_tv, color: Colors.white24, size: 64));
      return ValueListenableBuilder<bool>(
        valueListenable: v.buffering,
        builder: (context, buffering, _) => Stack(children: [
          Center(child: VlcVideoView(backend: v, fit: BoxFit.contain)),
          if (buffering) const Center(child: CircularProgressIndicator()),
        ]),
      );
    }
    final c = _controller;
    if (c == null) return const Center(child: Icon(Icons.live_tv, color: Colors.white24, size: 64));
    return Center(child: Video(controller: c, fit: BoxFit.contain));
  }
}
