import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../settings.dart';
import 'music_api.dart';

/// 播放模式（避免与 Flutter 3.50 material.dart 导出的 RepeatMode 撞名）
enum PlayMode { list, shuffle, one }

/// 队列条目：歌曲 + 解析后的播放地址（懒加载）
class QueueTrack {
  final MusicSong song;
  String? url;
  String quality;
  QueueTrack(this.song, {this.url, this.quality = AppSettings.defaultMusicQuality});
}

/// 全局音乐播放器（单例）。
/// 持有唯一 Player + VideoController，离开播放页不 dispose，音乐持续播放。
/// 由播放页负责把 Video controller 挂到真实纹理上（media_kit 桌面端需要）。
class GlobalMusicPlayer {
  static final GlobalMusicPlayer i = GlobalMusicPlayer._internal();
  GlobalMusicPlayer._internal();

  Player? _player;
  VideoController? _controller;
  bool _initialized = false;

  final List<QueueTrack> _queue = [];
  int _index = -1;
  int _generation = 0;
  bool _readyForCompleted = false;
  final List<int> _shuffleOrder = [];

  // ---- 对外可监听状态 ----
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<bool> buffering = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<double> volume = ValueNotifier(100);
  final ValueNotifier<double> speed = ValueNotifier(1.0);
  final ValueNotifier<PlayMode> repeatMode = ValueNotifier(PlayMode.list);
  final ValueNotifier<int> currentIndex = ValueNotifier(-1);
  final ValueNotifier<List<LrcLine>> lrcLines = ValueNotifier(const []);
  final ValueNotifier<int> lrcIndex = ValueNotifier(-1);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<int> revision = ValueNotifier(0); // 队列/曲目变化时 UI 刷新
  final ValueNotifier<String> currentQuality = ValueNotifier(AppSettings.defaultMusicQuality); // 当前曲目实际音质（降级后）
  final ValueNotifier<bool> ready = ValueNotifier(false); // 播放器就绪（触发隐藏 Video 挂载）

  Player get player {
    _ensureInitialized();
    return _player!;
  }
  VideoController get controller {
    _ensureInitialized();
    return _controller!;
  }
  bool get isInitialized => _initialized;
  List<QueueTrack> get queue => List.unmodifiable(_queue);
  QueueTrack? get current => (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  MusicSong? get currentSong => current?.song;

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    final p = Player();
    _player = p;
    _controller = VideoController(
      p,
      configuration: VideoControllerConfiguration(hwdec: AppSettings.i.hwdec.value),
    );
    p.stream.playing.listen((v) => playing.value = v);
    p.stream.buffering.listen((v) => buffering.value = v);
    p.stream.position.listen((v) {
      position.value = v;
      _updateLrcIndex(v);
    });
    p.stream.duration.listen((v) => duration.value = v);
    p.stream.volume.listen((v) => volume.value = v);
    p.stream.completed.listen((_) => _onCompleted());
    p.stream.error.listen((e) => error.value = e.toString());
    // 音质偏好变化：按新偏好重解当前曲目（即时生效）
    AppSettings.i.preferredQuality.addListener(_onQualityPreferenceChanged);
    ready.value = true;
  }

  /// 设置页改了「音乐音质」偏好后的回调：整队重算音质、清空已解析 url，
  /// 若正在播放则按新音质重新加载当前曲目（保留队列位置）。
  void _onQualityPreferenceChanged() {
    if (_queue.isEmpty) return;
    final pref = AppSettings.i.preferredQuality.value;
    for (final t in _queue) {
      final best = MusicQuality.best(t.song, pref);
      if (t.quality != best) {
        t.quality = best;
        t.url = null; // 强制重新解析播放地址
      }
    }
    if (_index >= 0 && _initialized) {
      // 重新打开当前曲目（setQuality 会清 url + 走 _playAt）
      _reloadCurrent();
    }
  }

  /// 用当前 track 重新解析地址并播放（保留 _index，不切歌）
  Future<void> _reloadCurrent() async {
    final t = current;
    if (t == null) return;
    final gen = ++_generation;
    _readyForCompleted = false;
    t.url = null;
    currentQuality.value = t.quality;
    try {
      t.url ??= (await MusicApi.url(t.song, quality: t.quality)).url;
      if (gen != _generation) return;
      await _player!.open(Media(t.url!));
      if (gen == _generation) {
        _loadLyric(t.song, gen);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (gen == _generation) _readyForCompleted = true;
        });
      }
    } catch (e) {
      if (gen == _generation) error.value = e.toString();
    }
  }

  /// 用一批歌曲开始播放（异步解析第一首的播放地址）
  Future<void> playSongs(List<MusicSong> songs, int startIndex) async {
    if (songs.isEmpty) return;
    _ensureInitialized();
    final pref = AppSettings.i.preferredQuality.value;
    _queue
      ..clear()
      ..addAll(songs.map((s) => QueueTrack(s, quality: MusicQuality.best(s, pref))));
    _index = startIndex.clamp(0, songs.length - 1);
    _buildShuffleOrder();
    error.value = null;
    revision.value++;
    await _playAt(_index);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final gen = ++_generation;
    _readyForCompleted = false;
    _index = index;
    currentIndex.value = index;
    lrcLines.value = const [];
    lrcIndex.value = -1;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    error.value = null;

    final track = _queue[index];
    currentQuality.value = track.quality;
    try {
      // 懒解析播放地址（优先音源脚本，需先启用音源）
      track.url ??= (await MusicApi.url(track.song, quality: track.quality)).url;
      if (gen != _generation) return;
      await _player!.open(Media(track.url!));
      if (gen != _generation) return;
      // 歌词异步加载
      _loadLyric(track.song, gen);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (gen == _generation) _readyForCompleted = true;
      });
    } catch (e) {
      if (gen == _generation) error.value = e.toString();
    }
  }

  Future<void> _loadLyric(MusicSong song, int gen) async {
    try {
      final lrc = await MusicApi.lyric(song);
      if (gen != _generation) return;
      lrcLines.value = parseLrc(lrc);
    } catch (_) {}
  }

  void _updateLrcIndex(Duration pos) {
    final lines = lrcLines.value;
    if (lines.isEmpty) return;
    int idx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (lrcIndex.value != idx) lrcIndex.value = idx;
  }

  void _onCompleted() {
    if (!_readyForCompleted || _queue.isEmpty) return;
    _readyForCompleted = false;
    switch (repeatMode.value) {
      case PlayMode.one:
        _playAt(_index);
        break;
      case PlayMode.shuffle:
        _playAt(_shuffleNext(1));
        break;
      case PlayMode.list:
      default:
        _playAt((_index + 1) % _queue.length);
        break;
    }
  }

  void playPause() {
    if (!_initialized) return;
    _player!.playOrPause();
  }
  void pause() {
    if (_initialized) _player!.pause();
  }
  void seek(Duration d) {
    if (_initialized) _player!.seek(d);
  }
  void setVolume(double v) {
    v = v.clamp(0.0, 100.0);
    volume.value = v;
    if (_initialized) _player!.setVolume(v);
  }
  void setSpeed(double s) {
    speed.value = s;
    if (_initialized) _player!.setRate(s);
  }
  void next() {
    if (_queue.isEmpty) return;
    _playAt(repeatMode.value == PlayMode.shuffle
        ? _shuffleNext(1)
        : (_index + 1) % _queue.length);
  }
  void previous() {
    if (_queue.isEmpty) return;
    _playAt(repeatMode.value == PlayMode.shuffle
        ? _shuffleNext(-1)
        : (_index - 1 + _queue.length) % _queue.length);
  }
  void playAt(int i) => _playAt(i);

  void cycleRepeat() {
    repeatMode.value = PlayMode.values[(repeatMode.value.index + 1) % PlayMode.values.length];
    if (repeatMode.value == PlayMode.shuffle) _buildShuffleOrder();
  }

  /// 切换当前曲目音质（重新解析播放地址）
  Future<void> setQuality(String quality) async {
    final t = current;
    if (t == null) return;
    t.quality = quality;
    t.url = null;
    await _playAt(_index);
  }

  void _buildShuffleOrder() {
    _shuffleOrder
      ..clear()
      ..addAll(List.generate(_queue.length, (i) => i))
      ..shuffle();
  }
  int _shuffleNext(int dir) {
    if (_shuffleOrder.isEmpty) _buildShuffleOrder();
    final pos = _shuffleOrder.indexOf(_index);
    if (pos < 0) return _shuffleOrder.isEmpty ? 0 : _shuffleOrder[0];
    return _shuffleOrder[(pos + dir + _shuffleOrder.length) % _shuffleOrder.length];
  }

  void disposeAll() {
    AppSettings.i.preferredQuality.removeListener(_onQualityPreferenceChanged);
    _player?.dispose();
    _player = null;
    _controller = null;
    _initialized = false;
    ready.value = false;
  }
}
