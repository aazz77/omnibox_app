// 全屏 MV 播放页（参考 FMusic 的 MvPlayerDialog）。
// 仅网易(wy)/酷狗(kg) 且歌曲有 MV 时可用：先用 mvInfo 补全 mv id，再用 mvUrl 拿直链，
// 由独立 media_kit Player + Video 全屏播放（与全局音乐播放器互不干扰）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../music/music_api.dart';

class MvPlayerPage extends StatefulWidget {
  final MusicSong song;
  const MvPlayerPage({required this.song, Key? key}) : super(key: key);

  /// 打开 MV 播放页；返回 true 表示确实播放了 MV（调用方可据此提示）。
  static Future<bool> open(BuildContext context, MusicSong song) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MvPlayerPage(song: song)),
    );
    return result ?? false;
  }

  @override
  State<MvPlayerPage> createState() => _MvPlayerPageState();
}

class _MvPlayerPageState extends State<MvPlayerPage> {
  final FocusNode _focus = FocusNode();
  Player? _player;
  VideoController? _controller;

  bool _loading = true;
  String? _error;
  String _title = '';
  String _resolvedMvId = '';
  bool _showControls = true;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _title = '${widget.song.name} - ${widget.song.singer}'.trim();
    // 桌面端无须隐藏系统栏；某些平台不支持 immersiveSticky，保护性 try。
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _prepare();
  }

  /// 1) 补全 mv id（搜索结果的 mv 常为 "0"）→ 2) 取直链 → 3) 建播放器
  Future<void> _prepare() async {
    setState(() { _loading = true; _error = null; });
    try {
      final mvId = await MusicApi.mvInfo(widget.song);
      if (mvId.isEmpty) {
        if (!mounted) return;
        setState(() { _loading = false; _error = '这首歌暂无 MV'; });
        return;
      }
      final url = await MusicApi.mvUrl(source: widget.song.source, mvId: mvId);
      if (!mounted) return;
      _resolvedMvId = mvId;
      final p = Player();
      final c = VideoController(p);
      p.stream.error.listen((e) {
        if (mounted) setState(() => _error = e.toString());
      });
      _player = p;
      _controller = c;
      await p.open(Media(url), play: true);
      if (!mounted) return;
      setState(() { _loading = false; _played = true; });
    } catch (e) {
      // open 失败时 player 可能已创建，确保释放，避免纹理泄漏
      await _player?.dispose();
      _player = null;
      _controller = null;
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(_played);
    } else if (e.logicalKey == LogicalKeyboardKey.space && _player != null) {
      _player!.playOrPause();
    }
  }

  @override
  void dispose() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    _player?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // 视频层
          if (_controller != null && _error == null)
            Positioned.fill(
              child: Video(
                controller: _controller!,
                controls: (state) => Stack(children: [
                  // 点击画面切换控制条显隐
                  Positioned.fill(child: GestureDetector(
                    onTap: _toggleControls,
                    behavior: HitTestBehavior.translucent,
                  )),
                  // media_kit 自带完整控制条（播放/进度/音量/全屏）
                  if (_showControls) AdaptiveVideoControls(state),
                ]),
              ),
            ),

          // 顶部悬浮标题栏：返回 + 歌名 + MV 标识
          if (_showControls && !_loading && _error == null)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(_played),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    _title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                  const Icon(Icons.music_video, color: Colors.white70, size: 20),
                ]),
              ),
            ),

          // 加载中
          if (_loading)
            const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text('正在加载 MV…', style: TextStyle(color: Colors.white70)),
            ])),

          // 错误 / 无 MV
          if (_error != null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.music_off, size: 56, color: Colors.white54),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                if (_error != '这首歌暂无 MV') ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: _prepare, child: const Text('重试')),
                ],
              ]),
            )),
        ]),
      ),
    );
  }
}
