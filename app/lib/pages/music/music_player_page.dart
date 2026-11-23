import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../app_core.dart';
import '../../settings.dart';
import '../../music/global_player.dart';
import '../../music/music_api.dart';
import 'mv_player_page.dart';

/// 音乐播放页（Nexus 风格全功能）：左封面 / 中歌词+控制 / 右队列。
/// 播放由全局单例 GlobalMusicPlayer 驱动，离开此页音乐继续播放。
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({Key? key}) : super(key: key);
  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final GlobalMusicPlayer _p = GlobalMusicPlayer.i;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showQueue = true;
  String? _coverUrl;

  @override
  void initState() {
    super.initState();
    // 监听曲目变化 → 加载封面（音质交给 currentQuality 广播）
    _p.currentIndex.addListener(_onTrackChanged);
    _onTrackChanged();
  }

  void _onTrackChanged() {
    final song = _p.currentSong;
    if (song == null) { if (mounted) setState(() => _coverUrl = null); return; }
    if (song.picUrl.startsWith('http')) {
      if (mounted) setState(() => _coverUrl = song.picUrl);
    } else {
      MusicApi.pic(song).then((u) {
        if (mounted && u.startsWith('http')) setState(() => _coverUrl = u);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _p.currentIndex.removeListener(_onTrackChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 播放当前歌曲的 MV（仅 wy/kg）。无 MV 时给出明确提示，不静默失败。
  Future<void> _openMv() async {
    final song = _p.currentSong;
    if (song == null) return;
    if (!song.mvSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅网易云 / 酷狗的歌曲支持 MV 播放')),
      );
      return;
    }
    // 先异步补全 mv id（搜索结果 mv 常为 "0"），再决定是否进播放页。
    // showSnackBar 需要 context 仍挂载；若补全后无 MV 直接提示。
    String mvId;
    try {
      mvId = await MusicApi.mvInfo(song);
    } catch (_) {
      mvId = '';
    }
    if (!mounted) return;
    if (mvId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这首歌暂无 MV')),
      );
      return;
    }
    final songWithMv = MusicSong(
      source: song.source, songmid: song.songmid, name: song.name,
      singer: song.singer, albumName: song.albumName, albumId: song.albumId,
      interval: song.interval, hash: song.hash, picUrl: song.picUrl,
      types: song.types, mv: mvId,
    );
    await MvPlayerPage.open(context, songWithMv);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.music_video),
            tooltip: '播放MV',
            onPressed: _openMv,
          ),
          IconButton(
            icon: Icon(_showQueue ? Icons.queue_music : Icons.queue_music_outlined),
            tooltip: '播放队列',
            onPressed: () => setState(() => _showQueue = !_showQueue),
          ),
        ],
      ),
      body: Row(children: [
        // 左：封面（固定宽度）
        SizedBox(width: 300, child: _CoverPanel(coverUrl: _coverUrl)),
        const VerticalDivider(width: 1),
        // 中：歌词 + 控制
        Expanded(child: Column(children: [
          Expanded(child: _LyricsView(p: _p)),
          const Divider(height: 1),
          ValueListenableBuilder<String>(
            valueListenable: _p.currentQuality,
            builder: (context, q, _) => _Controls(p: _p, quality: q, onQuality: (v) async {
              await _p.setQuality(v);
            }),
          ),
        ])),
        // 右：队列
        if (_showQueue)
          SizedBox(width: 320, child: _QueuePanel(p: _p, onClose: () => setState(() => _showQueue = false))),
      ]),
    );
  }
}

// ===== 隐藏的 mpv 渲染纹理（保活播放管线，桌面端纯音频也需要）=====
class HiddenMusicSink extends StatefulWidget {
  const HiddenMusicSink({Key? key}) : super(key: key);
  @override
  State<HiddenMusicSink> createState() => _HiddenMusicSinkState();
}
class _HiddenMusicSinkState extends State<HiddenMusicSink> {
  @override
  Widget build(BuildContext context) {
    final p = GlobalMusicPlayer.i;
    return ValueListenableBuilder<bool>(
      valueListenable: p.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        return SizedBox(
          width: 1, height: 1,
          child: Video(controller: p.controller, controls: (_) => const SizedBox.shrink()),
        );
      },
    );
  }
}

// ===== 封面 =====
class _CoverPanel extends StatelessWidget {
  final String? coverUrl;
  const _CoverPanel({required this.coverUrl});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (coverUrl != null && coverUrl!.startsWith('http'))
                  ? NetImage(coverUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                  : Container(
                      color: Colors.indigo.shade100,
                      child: const Icon(Icons.album, size: 96, color: Colors.indigo),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<int>(
            valueListenable: GlobalMusicPlayer.i.currentIndex,
            builder: (context, idx, _) {
              final song = GlobalMusicPlayer.i.currentSong;
              if (song == null) return const Text('未播放');
              return Column(children: [
                Text(song.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(song.singer, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

// ===== 歌词 =====
class _LyricsView extends StatefulWidget {
  final GlobalMusicPlayer p;
  const _LyricsView({required this.p});
  @override
  State<_LyricsView> createState() => _LyricsViewState();
}
class _LyricsViewState extends State<_LyricsView> {
  final ScrollController _scroll = ScrollController();
  void _onLrc() {
    final idx = widget.p.lrcIndex.value;
    final lines = widget.p.lrcLines.value;
    if (idx >= 0 && idx < lines.length && _scroll.hasClients) {
      _scroll.animateTo((idx * 40.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }
  @override
  void initState() {
    super.initState();
    widget.p.lrcIndex.addListener(_onLrc);
  }
  @override
  void dispose() {
    widget.p.lrcIndex.removeListener(_onLrc);
    _scroll.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LrcLine>>(
      valueListenable: widget.p.lrcLines,
      builder: (context, lines, _) {
        if (lines.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lyrics_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('暂无歌词', style: TextStyle(color: Colors.grey.shade500)),
          ]));
        }
        return ValueListenableBuilder<int>(
          valueListenable: widget.p.lrcIndex,
          builder: (context, active, _) => ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 120),
            itemCount: lines.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
              child: Text(
                lines[i].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: i == active ? 18 : 15,
                  fontWeight: i == active ? FontWeight.bold : FontWeight.normal,
                  color: i == active ? Colors.indigo : Colors.grey.shade500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ===== 控制条 =====
class _Controls extends StatelessWidget {
  final GlobalMusicPlayer p;
  final String quality;
  final ValueChanged<String> onQuality;
  const _Controls({required this.p, required this.quality, required this.onQuality});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(children: [
        // 进度条
        ValueListenableBuilder<Duration>(
          valueListenable: p.position,
          builder: (context, pos, _) => ValueListenableBuilder<Duration>(
            valueListenable: p.duration,
            builder: (context, dur, _) {
              final maxMs = dur.inMilliseconds.toDouble();
              final sliderMax = maxMs > 0 ? maxMs : 1.0;
              final sliderValue = pos.inMilliseconds.toDouble().clamp(0.0, sliderMax).toDouble();
              return Column(children: [
              Slider(
                value: sliderValue,
                max: sliderMax,
                onChanged: (v) => p.seek(Duration(milliseconds: v.toInt())),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(fmtDuration(pos), style: const TextStyle(fontSize: 11)),
                  Text(fmtDuration(dur), style: const TextStyle(fontSize: 11)),
                ]),
              ),
              ]);
            },
          ),
        ),
        const SizedBox(height: 4),
        // 播放控制
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // 模式
          ValueListenableBuilder<PlayMode>(
            valueListenable: p.repeatMode,
            builder: (context, mode, _) => IconButton(
              icon: Icon(_repeatIcon(mode), color: mode == PlayMode.shuffle ? Colors.indigo : null),
              tooltip: _repeatLabel(mode),
              onPressed: p.cycleRepeat,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(icon: const Icon(Icons.skip_previous, size: 32), onPressed: p.previous),
          const SizedBox(width: 12),
          ValueListenableBuilder<bool>(
            valueListenable: p.playing,
            builder: (context, playing, _) => CircleAvatar(
              radius: 26,
              backgroundColor: Colors.indigo,
              child: IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: p.playPause,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(icon: const Icon(Icons.skip_next, size: 32), onPressed: p.next),
          const SizedBox(width: 12),
          // 音质（下拉显示中文名，实际值可能按歌曲支持能力降级）
          DropdownButton<String>(
            value: quality,
            items: [for (final o in AppSettings.musicQualityOptions) DropdownMenuItem(value: o.value, child: Text(o.label))],
            onChanged: (q) { if (q != null) onQuality(q); },
            underline: const SizedBox.shrink(),
            isDense: true,
          ),
        ]),
        const SizedBox(height: 6),
        // 音量 + 倍速
        Row(children: [
          const Icon(Icons.volume_down, size: 18),
          SizedBox(
            width: 140,
            child: ValueListenableBuilder<double>(
              valueListenable: p.volume,
              builder: (context, vol, _) => Slider(value: vol, min: 0, max: 100, onChanged: p.setVolume),
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<double>(
            valueListenable: p.speed,
            builder: (context, speed, _) => DropdownButton<double>(
              value: speed,
              items: [for (final s in [0.75, 1.0, 1.25, 1.5, 2.0]) DropdownMenuItem(value: s, child: Text('${s}x'))],
              onChanged: (v) { if (v != null) p.setSpeed(v); },
              underline: const SizedBox.shrink(),
            ),
          ),
        ]),
        // 音质降级提示：偏好高于实际可用音质时给出说明（对齐 lx-server）
        ValueListenableBuilder<String>(
          valueListenable: AppSettings.i.preferredQuality,
          builder: (context, pref, _) {
            final pi = MusicQuality.priority.indexOf(pref);
            final qi = MusicQuality.priority.indexOf(quality);
            if (pi < 0 || qi <= pi) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '偏好「${MusicQuality.label(pref)}」不可用时，已降级为「${MusicQuality.label(quality)}」播放',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            );
          },
        ),
        // 错误提示
        ValueListenableBuilder<String?>(
          valueListenable: p.error,
          builder: (context, err, _) => err == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
                ),
        ),
      ]),
    );
  }

  IconData _repeatIcon(PlayMode m) {
    switch (m) {
      case PlayMode.one:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
      case PlayMode.list:
      default:
        return Icons.repeat_rounded;
    }
  }
  String _repeatLabel(PlayMode m) {
    switch (m) {
      case PlayMode.one:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
      case PlayMode.list:
      default:
        return '列表循环';
    }
  }
}

// ===== 播放队列 =====
class _QueuePanel extends StatelessWidget {
  final GlobalMusicPlayer p;
  final VoidCallback onClose;
  const _QueuePanel({required this.p, required this.onClose});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          const Icon(Icons.queue_music, size: 18),
          const SizedBox(width: 6),
          ValueListenableBuilder<int>(
            valueListenable: p.currentIndex,
            builder: (context, idx, _) => Text('播放队列 (${p.queue.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ValueListenableBuilder<int>(
        valueListenable: p.currentIndex,
        builder: (context, cur, _) => ListView.builder(
          itemCount: p.queue.length,
          itemBuilder: (context, i) {
            final s = p.queue[i].song;
            return ListTile(
              dense: true,
              selected: i == cur,
              leading: Text('${i + 1}', style: TextStyle(color: i == cur ? Colors.indigo : Colors.grey, fontSize: 12)),
              title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: i == cur ? Colors.indigo : null, fontWeight: i == cur ? FontWeight.bold : null)),
              subtitle: Text(s.singer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              onTap: () => p.playAt(i),
            );
          },
        ),
      )),
    ]);
  }
}
