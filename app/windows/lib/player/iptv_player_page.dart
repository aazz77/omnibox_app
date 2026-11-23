// IPTV 直播播放页（对齐 Nexus 的 iptv_player_page.dart，简化为工程内既有依赖）。
// 布局：左侧 7 视频区 + 右侧固定 360 频道面板（分组 80 / 频道 flex / 线路 72）。
// 全屏为应用内沉浸模式（隐藏频道面板，视频铺满整页），不引入 window_manager，
// 用 GlobalKey 让 VlcPlayer 的 State 在分屏↔全屏间移动而非重建，避免黑屏。
// 本页通过 Navigator.push 打开（独立 Scaffold），不走主壳的 NavigationRail，
// 因此播放页不显示左侧导航栏。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../iptv/iptv_sources.dart';
import '../settings.dart';
import '../iptv/m3u_parser.dart';
import 'vlc_player.dart';

/// 播放参数（由源管理页点击源卡片时传入）
class IptvPlayArgs {
  final int sourceIndex;
  final String sourceName;
  IptvPlayArgs({required this.sourceIndex, required this.sourceName});
}

class IptvPlayerPage extends StatefulWidget {
  final IptvPlayArgs args;
  const IptvPlayerPage({required this.args, Key? key}) : super(key: key);

  @override
  State<IptvPlayerPage> createState() => _IptvPlayerPageState();
}

class _IptvPlayerPageState extends State<IptvPlayerPage> {
  late final VlcController _vlc;

  final List<M3uChannel> _channels = [];
  Map<String, List<M3uChannel>> _grouped = {};
  String _browseGroup = '';
  String _playingGroup = '';
  String _channelName = '';
  List<String> _streamUrls = [];
  int _streamIndex = 0;

  bool _loading = true;
  bool _immersive = false;
  bool _showControls = true;
  Timer? _hideTimer;

  final ScrollController _channelScroll = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _vlc = VlcController(hardwareDecode: AppSettings.i.iptvHwdec.value);
    _vlc.playing.addListener(_onVlc);
    _vlc.buffering.addListener(_onVlc);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _loadSource();
  }

  void _onVlc() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSource() async {
    setState(() => _loading = true);
    try {
      final parsed = await IptvStore.i.loadChannels(widget.args.sourceIndex);
      if (!mounted) return;
      final grouped = M3uParser.groupBy(parsed);
      if (grouped.isEmpty) {
        setState(() {
          _channels
            ..clear()
            ..addAll(parsed);
          _grouped = grouped;
          _loading = false;
        });
        return;
      }
      final firstGroup = grouped.keys.first;
      final firstCh = grouped[firstGroup]!.first;
      setState(() {
        _channels
          ..clear()
          ..addAll(parsed);
        _grouped = grouped;
        _browseGroup = firstGroup;
        _loading = false;
      });
      _selectChannel(firstCh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载 IPTV 源失败: $e')),
      );
    }
  }

  List<String> get _groups => _grouped.keys.toList();

  List<M3uChannel> get _browsedChannels {
    if (_browseGroup.isEmpty) return [];
    final seen = <String>{};
    return (_grouped[_browseGroup] ?? [])
        .where((c) => seen.add(c.name))
        .toList();
  }

  void _selectChannel(M3uChannel ch) {
    final urls = _channels
        .where((c) => c.name == ch.name)
        .map((c) => c.url)
        .toSet()
        .toList();
    final list = urls.isNotEmpty ? urls : [ch.url];
    setState(() {
      _channelName = ch.name;
      _playingGroup = ch.group;
      _streamUrls = list;
      _streamIndex = 0;
    });
    _vlc.open(list.first);
    _kickHideTimer();
  }

  void _selectStream(int idx) {
    if (idx < 0 || idx >= _streamUrls.length) return;
    setState(() => _streamIndex = idx);
    _vlc.open(_streamUrls[idx]);
    _kickHideTimer();
  }

  void _kickHideTimer({int seconds = 3}) {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    if (e.logicalKey == LogicalKeyboardKey.space) {
      _vlc.playOrPause();
      _kickHideTimer();
    } else if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (_immersive) {
        setState(() => _immersive = false);
      } else {
        Navigator.of(context).pop();
      }
    } else if (e.logicalKey == LogicalKeyboardKey.keyF) {
      setState(() => _immersive = !_immersive);
      _kickHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _vlc.playing.removeListener(_onVlc);
    _vlc.buffering.removeListener(_onVlc);
    _vlc.dispose();
    _channelScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Row(
          children: [
            Expanded(flex: 7, child: _videoArea()),
            if (!_immersive)
              SizedBox(width: 360, child: _channelPanel()),
          ],
        ),
      ),
    );
  }

  Widget _videoArea() {
    return MouseRegion(
      onHover: (_) => _kickHideTimer(),
      onEnter: (_) => _kickHideTimer(),
      cursor: SystemMouseCursors.basic,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VlcVideoView(
            backend: _vlc,
            fill: Colors.black,
            playerKey: _playerKey,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _vlc.buffering,
            builder: (context, buffering, _) => buffering
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : const SizedBox(),
          ),
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: Stack(
              children: [
                _topBar(),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
              tooltip: '返回',
              onPressed: () => _immersive
                  ? setState(() => _immersive = false)
                  : Navigator.of(context).pop(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _channelName.isEmpty ? widget.args.sourceName : _channelName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('LIVE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
        child: Row(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _vlc.playing,
              builder: (context, playing, _) => IconButton(
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => _vlc.playOrPause(),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.volume_up, color: Colors.white70, size: 18),
            ValueListenableBuilder<double>(
              valueListenable: _vlc.volume,
              builder: (context, vol, _) => SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: vol.clamp(0, 100),
                    min: 0,
                    max: 100,
                    onChanged: (v) => _vlc.setVolume(v),
                  ),
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _immersive
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
                size: 26,
              ),
              tooltip: _immersive ? '退出全屏' : '全屏',
              onPressed: () =>
                  setState(() => _immersive = !_immersive),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant.withAlpha(60))),
            ),
            child: Text(
              _channelName.isEmpty ? 'IPTV' : _channelName,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _grouped.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.live_tv_outlined,
                                size: 48,
                                color: scheme.onSurfaceVariant.withAlpha(80)),
                            const SizedBox(height: 12),
                            const Text('暂无频道',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 80, child: _groupColumn()),
                          VerticalDivider(
                              width: 1,
                              color: scheme.outlineVariant.withAlpha(80)),
                          Expanded(child: _channelColumn()),
                          VerticalDivider(
                              width: 1,
                              color: scheme.outlineVariant.withAlpha(80)),
                          SizedBox(width: 72, child: _streamColumn()),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _groupColumn() {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _groups.length,
      itemBuilder: (_, i) {
        final g = _groups[i];
        final isBrowsing = _browseGroup == g;
        final isPlaying = _playingGroup == g;
        return InkWell(
          onTap: () => setState(() {
            _browseGroup = g;
            _channelScroll.jumpTo(0);
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: isBrowsing
                  ? scheme.primary
                  : isPlaying
                      ? scheme.primaryContainer.withAlpha(120)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              g,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isBrowsing
                    ? scheme.onPrimary
                    : isPlaying
                        ? scheme.primary
                        : scheme.onSurface,
                fontWeight: (isBrowsing || isPlaying)
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _channelColumn() {
    final scheme = Theme.of(context).colorScheme;
    final list = _browsedChannels;
    if (list.isEmpty) {
      return Center(
        child: Text('请选择分组',
            style: TextStyle(
                fontSize: 12, color: scheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      controller: _channelScroll,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final ch = list[i];
        final selected = _channelName == ch.name;
        return InkWell(
          onTap: () => _selectChannel(ch),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            color: selected
                ? scheme.primaryContainer.withAlpha(180)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                if (ch.logo.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.network(
                      ch.logo,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _logoIcon(scheme),
                    ),
                  )
                else
                  _logoIcon(scheme),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.play_arrow_rounded,
                      size: 13, color: scheme.primary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _logoIcon(ColorScheme scheme) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withAlpha(60),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(Icons.live_tv, size: 13, color: scheme.primary),
      );

  Widget _streamColumn() {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _streamUrls.length,
      itemBuilder: (_, i) {
        final isSelected = _streamIndex == i;
        return InkWell(
          onTap: () => _selectStream(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '源${i + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
