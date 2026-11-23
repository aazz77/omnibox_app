// 弹幕渲染层：叠加在播放器上，按视频播放时间排程弹幕。
// 逻辑复刻 danmu-anywhere 插件的 DanmuRenderer：
//   - 按 player.stream.position（视频时间）排程，暂停即静止
//   - 滚动弹幕轨道分配 + 防重叠（尾巴清 + 追尾预判）
//   - seek 清屏 + 指针二分重定位；快进不补放（GRACE 0.5s）、倒回可重看
//   - 顶部/底部固定弹幕占轨 5s
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import '../app_core.dart';
import '../settings.dart';

const List<Color> _kPalette = [
  Color(0xffffffff), Color(0xff70f3ff), Color(0xff44cef6), Color(0xff3eede7),
  Color(0xff00e079), Color(0xff2edfa3), Color(0xffbce672), Color(0xfffff143),
  Color(0xffffa631), Color(0xffff7500), Color(0xffff4e20), Color(0xffff2d51),
  Color(0xffef7a82), Color(0xffff0097), Color(0xffb0a4e3), Color(0xff4b5cc4),
];

class _Lane {
  final int index;
  _Lane(this.index);
  double lastStart = -1e9;
  double lastTextW = 0;
  double lastPx = 0;
  double lastDur = 0;
}

class _Active {
  final DanmuItem item;
  final double start; // 视频时间（秒）
  final bool scroll;
  final int laneIndex;
  final double textW;
  final double pxSpeed;
  final double dur;
  final double top;
  final Color color;
  final double fontSize;
  _Active({
    required this.item, required this.start, required this.scroll,
    required this.laneIndex, required this.textW, required this.pxSpeed,
    required this.dur, required this.top, required this.color, required this.fontSize,
  });
}

/// 弹幕覆盖层。铺满父容器（需放在 Stack 内）。
class DanmuOverlay extends StatefulWidget {
  /// 时间源二选一：mpv 传 player，VLC 传 positionStream。
  final Player? player;
  final Stream<Duration>? positionStream;
  final List<DanmuItem> items;
  const DanmuOverlay({
    this.player,
    this.positionStream,
    required this.items,
    Key? key,
  }) : assert(player != null || positionStream != null,
            'DanmuOverlay 需要 player 或 positionStream 之一'),
        super(key: key);
  @override
  State<DanmuOverlay> createState() => _DanmuOverlayState();
}

class _DanmuOverlayState extends State<DanmuOverlay> with TickerProviderStateMixin {
  StreamSubscription<Duration>? _posSub;
  Ticker? _ticker;
  List<DanmuItem> _items = [];
  int _pointer = 0;
  final List<_Active> _active = [];
  List<_Lane> _scrollLanes = [];
  List<_Lane> _topLanes = [];
  List<_Lane> _bottomLanes = [];
  double _W = 0;
  double _H = 0;
  double _now = 0;
  double _lastNow = 0;
  final TextPainter _measure = TextPainter(textDirection: TextDirection.ltr);

  DanmuConfig get _cfg => AppSettings.i.danmu.value;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    _resetLanes();
    _posSub = (widget.positionStream ?? widget.player!.stream.position).listen(_onPosition);
    // 每帧驱动重绘：弹幕滚动不依赖 position stream 推送频率（保证流畅）
    _ticker = createTicker(_onFrame)..start();
    AppSettings.i.danmu.addListener(_onConfigChanged);
  }

  void _onFrame(Duration elapsed) {
    _tick(_now);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(DanmuOverlay old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player || old.positionStream != widget.positionStream) {
      _posSub?.cancel();
      _posSub = (widget.positionStream ?? widget.player!.stream.position).listen(_onPosition);
    }
    if (!identical(old.items, widget.items)) {
      _items = widget.items;
      _clear(); // 换弹幕源：整批作废
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ticker?.stop();
    AppSettings.i.danmu.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (!mounted) return;
    // 字号/行数/间距变化会让已有轨道位置失效：清屏重排（数据保留）
    if (mounted) setState(() { _clear(); });
  }

  void _clear() {
    _active.clear();
    _pointer = 0;
    _resetLanes();
  }

  void _resetLanes() {
    final n = _cfg.lines.clamp(1, 30).toInt();
    _scrollLanes = List.generate(n, (i) => _Lane(i));
    _topLanes = List.generate(n, (i) => _Lane(i));
    _bottomLanes = List.generate(n, (i) => _Lane(i));
  }

  double _baseFont() => _H <= 0 ? 18 : (18 + (_H / 24).round()).clamp(14, 28).toDouble();

  TextStyle _textStyle(double fs) => TextStyle(
        fontSize: fs,
        fontWeight: FontWeight.w500,
        fontFamily: 'Microsoft YaHei',
        color: Colors.white,
      );

  double _textWidth(String text, double fs) {
    _measure.text = TextSpan(text: text, style: _textStyle(fs));
    _measure.layout();
    return _measure.width;
  }

  void _onPosition(Duration d) {
    final now = d.inMilliseconds / 1000.0;
    if ((now - _lastNow).abs() > 1.0) {
      _onSeek(now); // 跳转（拖进度/换集）：清屏重定位
    }
    _lastNow = now;
    _now = now; // 实际排程由 Ticker 每帧用该值驱动
  }

  /// seek：清屏 + 指针二分定位（快进不补放，倒回可重看）
  void _onSeek(double now) {
    _active.clear();
    _resetLanes();
    final t = now - 0.05;
    int lo = 0, hi = _items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_items[mid].time < t) lo = mid + 1; else hi = mid;
    }
    _pointer = lo;
  }

  void _tick(double now) {
    _now = now;
    if (_items.isEmpty || !_cfg.open) return;
    if (_W <= 0 || _H <= 0) return;
    // 发射到点时弹幕（0.5s 容差内才发，避免快进时一次性塞屏）
    while (_pointer < _items.length && _items[_pointer].time <= now) {
      final item = _items[_pointer++];
      if (now - item.time <= 0.5) _place(item, now);
    }
    // 到期移除
    _active.removeWhere((rec) => now - rec.start > rec.dur);
  }

  void _place(DanmuItem item, double now) {
    final cfg = _cfg;
    final fs = (_baseFont() * cfg.size).round().toDouble();
    final laneH = fs + cfg.spacing.toDouble();
    final textW = _textWidth(item.text, fs);
    final useColor = cfg.randomColor
        ? _kPalette[(DateTime.now().microsecondsSinceEpoch + item.time.toInt()) % _kPalette.length]
        : _parseColor(item.color);

    if (item.mode >= 1 && item.mode <= 3) {
      final pxSpeed = (_W + textW) / (8.0 * cfg.speed);
      final lane = _allocLane(_scrollLanes, item.time, textW, pxSpeed, 0);
      if (lane == null) return;
      lane.lastStart = item.time;
      lane.lastTextW = textW;
      lane.lastPx = pxSpeed;
      final dur = (_W + textW) / pxSpeed;
      lane.lastDur = dur;
      _active.add(_Active(
        item: item, start: item.time, scroll: true, laneIndex: lane.index,
        textW: textW, pxSpeed: pxSpeed, dur: dur,
        top: cfg.top.toDouble() + lane.index * laneH, color: useColor, fontSize: fs,
      ));
    } else if (item.mode == 4 || item.mode == 5) {
      final lanes = item.mode == 4 ? _bottomLanes : _topLanes;
      final lane = _allocLane(lanes, item.time, textW, 0, 5);
      if (lane == null) return;
      lane.lastStart = item.time;
      final top = item.mode == 5
          ? cfg.top.toDouble() + lane.index * laneH
          : _H - (lane.index + 1) * laneH;
      _active.add(_Active(
        item: item, start: item.time, scroll: false, laneIndex: lane.index,
        textW: textW, pxSpeed: 0, dur: 5,
        top: top, color: useColor, fontSize: fs,
      ));
    }
  }

  /// 轨道分配：空闲轨直接返回；滚动轨需满足尾巴已清 + 不会追尾；固定轨按占用时长排队。
  _Lane? _allocLane(List<_Lane> lanes, double itemTime, double textW, double newPx, double busySec) {
    for (final lane in lanes) {
      if (lane.lastStart < -1e8) return lane;
      if (busySec > 0) {
        if (itemTime - lane.lastStart >= busySec) return lane;
        continue;
      }
      final dt = itemTime - lane.lastStart;
      if (dt * lane.lastPx < lane.lastTextW + 32) continue; // 尾巴未清
      if (dt < lane.lastDur && (lane.lastDur - dt) * newPx > _W) continue; // 会追尾
      return lane;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      _W = constraints.maxWidth.isFinite ? constraints.maxWidth : 0;
      _H = constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
      final cfg = _cfg;
      if (!cfg.open || _items.isEmpty || _W <= 0 || _H <= 0) {
        return const IgnorePointer(child: SizedBox.expand());
      }
      return IgnorePointer(
        child: SizedBox.expand(
          child: CustomPaint(painter: _DanmuPainter(_active, _now, _W, _H, cfg.alpha)),
        ),
      );
    });
  }
}

Color _parseColor(String s) {
  if (s.startsWith('#')) {
    final hex = s.substring(1).replaceAll('#', '');
    if (hex.length >= 6) {
      final v = int.tryParse(hex.substring(0, 6), radix: 16);
      if (v != null) return Color(0xff000000 | v);
    }
  }
  return const Color(0xffffffff);
}

class _DanmuPainter extends CustomPainter {
  final List<_Active> active;
  final double now;
  final double W;
  final double H;
  final double alpha;
  final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);

  _DanmuPainter(this.active, this.now, this.W, this.H, this.alpha);

  @override
  void paint(Canvas canvas, Size size) {
    for (final rec in active) {
      final prog = now - rec.start;
      double x;
      if (rec.scroll) {
        x = W - prog * rec.pxSpeed;
        if (x + rec.textW < 0 || x > W) continue; // 出屏跳过
      } else {
        x = (W - rec.textW) / 2;
      }
      _tp.text = TextSpan(
        text: rec.item.text,
        style: TextStyle(
          fontSize: rec.fontSize,
          fontWeight: FontWeight.w500,
          fontFamily: 'Microsoft YaHei',
          color: rec.color.withOpacity(alpha),
          shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Color(0x99000000))],
        ),
      );
      _tp.layout();
      _tp.paint(canvas, Offset(x, rec.top));
    }
  }

  @override
  bool shouldRepaint(_DanmuPainter old) => true;
}
