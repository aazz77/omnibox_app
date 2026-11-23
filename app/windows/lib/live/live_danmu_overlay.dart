// 直播实时弹幕层：事件驱动（收到即上屏），按墙钟时间滚动。
// 数据来自 LiveApi.danmuPoll 轮询；渲染参数来自 AppSettings.i.liveDanmu。
// 与点播弹幕层（按视频时间排程）完全独立，铺满父容器，需放在 Stack 内。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../settings.dart';
import 'live_api.dart';

const List<Color> _kPalette = [
  Color(0xffffffff), Color(0xff70f3ff), Color(0xff44cef6), Color(0xff3eede7),
  Color(0xff00e079), Color(0xff2edfa3), Color(0xffbce672), Color(0xfffff143),
  Color(0xffffa631), Color(0xffff7500), Color(0xffff4e20), Color(0xffff2d51),
  Color(0xffef7a82), Color(0xffff0097), Color(0xffb0a4e3), Color(0xff4b5cc4),
];

class _Active {
  final String text;
  final Color color;
  final double start; // 墙钟秒
  final double dur;
  final double textW;
  final int lane;
  final double fontSize;
  final bool bold;
  final bool stroke;
  final double opacity;
  _Active({
    required this.text, required this.color, required this.start, required this.dur,
    required this.textW, required this.lane, required this.fontSize,
    required this.bold, required this.stroke, required this.opacity,
  });
}

/// 直播弹幕覆盖层。外部把轮询到的消息塞进 [incoming]（ValueNotifier），
/// 本层监听它并把 chat 类型消息排入轨道。
class LiveDanmuOverlay extends StatefulWidget {
  final ValueNotifier<List<LiveDanmuMessage>> incoming;
  const LiveDanmuOverlay({required this.incoming, Key? key}) : super(key: key);
  @override
  State<LiveDanmuOverlay> createState() => _LiveDanmuOverlayState();
}

class _LiveDanmuOverlayState extends State<LiveDanmuOverlay> with TickerProviderStateMixin {
  Ticker? _ticker;
  final List<_Active> _active = [];
  final List<double> _laneLastStart = [];
  final List<double> _laneLastW = [];
  double _W = 0, _H = 0;
  double _now = 0;
  final TextPainter _measure = TextPainter(textDirection: TextDirection.ltr);
  int _colorCursor = 0;

  LiveDanmuConfig get _cfg => AppSettings.i.liveDanmu.value;

  @override
  void initState() {
    super.initState();
    widget.incoming.addListener(_onIncoming);
    _ticker = createTicker(_onFrame)..start();
    AppSettings.i.liveDanmu.addListener(_onCfg);
  }

  @override
  void didUpdateWidget(LiveDanmuOverlay old) {
    super.didUpdateWidget(old);
    if (old.incoming != widget.incoming) {
      old.incoming.removeListener(_onIncoming);
      widget.incoming.addListener(_onIncoming);
    }
  }

  @override
  void dispose() {
    widget.incoming.removeListener(_onIncoming);
    AppSettings.i.liveDanmu.removeListener(_onCfg);
    _ticker?.stop();
    super.dispose();
  }

  void _onCfg() {
    if (!mounted) return;
    setState(() {
      if (!_cfg.enabled) _active.clear();
      _resetLanes();
    });
  }

  void _resetLanes() {
    final areaTop = _H * (1 - _cfg.area / 100).clamp(0.0, 0.8);
    final usable = _H - areaTop;
    final laneH = _cfg.fontSize + _cfg.lineGap;
    final n = (usable / laneH).floor().clamp(1, 12);
    if (_laneLastStart.length != n) {
      _laneLastStart.clear();
      _laneLastW.clear();
      for (int i = 0; i < n; i++) { _laneLastStart.add(-1e9); _laneLastW.add(0); }
    }
  }

  void _onIncoming() {
    final cfg = _cfg;
    if (!cfg.enabled || !mounted) return;
    final batch = widget.incoming.value;
    if (batch.isEmpty) return;
    widget.incoming.value = []; // 消费掉，避免重复处理
    _resetLanes();
    for (final m in batch) {
      if (m.type != 'chat' || m.message.isEmpty) continue;
      _spawn(m);
    }
    setState(() {});
  }

  void _spawn(LiveDanmuMessage m) {
    final cfg = _cfg;
    final text = cfg.showUser && m.userName.isNotEmpty ? '${m.userName}: ${m.message}' : m.message;
    final fontSize = cfg.fontSize.toDouble();
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: cfg.bold ? FontWeight.bold : FontWeight.normal,
    );
    _measure.text = TextSpan(text: text, style: style);
    _measure.layout(maxWidth: 1e6);
    final textW = _measure.width;
    final dur = cfg.duration.toDouble();
    final speed = (_W + textW) / dur; // px/s

    // 选最空闲轨道：要求上一条尾巴已离开起点 + 水平间距
    int chosen = 0;
    double bestGap = -1e9;
    for (int i = 0; i < _laneLastStart.length; i++) {
      final elapsed = _now - _laneLastStart[i];
      final headX = _W - speed * elapsed; // 上一条当前头位置
      // 上一条尾部完全进入屏幕左边界后 + 水平间距，才允许下一条同轨
      final gap = (headX + _laneLastW[i] + cfg.itemGap) * -1;
      if (gap < 0) { chosen = i; bestGap = 0; break; }
      if (bestGap < 0 || gap < bestGap) { bestGap = gap; chosen = i; }
    }

    Color color;
    switch (cfg.colorMode) {
      case 'custom':
        color = _hexColor(cfg.color);
        break;
      case 'white':
        color = Colors.white;
        break;
      case 'rainbow':
        color = _kPalette[_colorCursor++ % _kPalette.length];
        break;
      default: // platform：用平台下发颜色
        color = Color(m.color | 0xff000000);
    }
    if (cfg.opacity < 1) {
      color = color.withValues(alpha: cfg.opacity);
    }

    _active.add(_Active(
      text: text, color: color, start: _now, dur: dur, textW: textW,
      lane: chosen, fontSize: fontSize, bold: cfg.bold,
      stroke: cfg.stroke, opacity: cfg.opacity,
    ));
    _laneLastStart[chosen] = _now;
    _laneLastW[chosen] = textW;
  }

  Color _hexColor(String s) {
    final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
    return v == null ? Colors.white : Color(0xff000000 | v);
  }

  void _onFrame(Duration elapsed) {
    _now = elapsed.inMilliseconds / 1000.0;
    final cfg = _cfg;
    // 墙钟推进：剔除已滚出屏幕的弹幕
    final speedOf = (double textW) => (_W + textW) / cfg.duration.toDouble();
    _active.removeWhere((a) {
      final s = speedOf(a.textW);
      return _now - a.start > (_W + a.textW) / s + 0.2;
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _W = box.maxWidth;
      _H = box.maxHeight;
      _resetLanes();
      return IgnorePointer(
        child: CustomPaint(painter: _Painter(_active, _now, _W, _H, _cfg)),
      );
    });
  }
}

class _Painter extends CustomPainter {
  final List<_Active> active;
  final double now, W, H;
  final LiveDanmuConfig cfg;
  _Painter(this.active, this.now, this.W, this.H, this.cfg);

  @override
  void paint(Canvas canvas, Size size) {
    final areaTop = H * (1 - cfg.area / 100).clamp(0.0, 0.8);
    final laneH = cfg.fontSize + cfg.lineGap;
    for (final a in active) {
      final speed = (W + a.textW) / cfg.duration.toDouble();
      final elapsed = now - a.start;
      final x = W - speed * elapsed;
      final y = areaTop + a.lane * laneH;
      final tp = TextPainter(
        text: TextSpan(
          text: a.text,
          style: TextStyle(
            color: a.color, fontSize: a.fontSize,
            fontWeight: a.bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (a.stroke) {
        // 描边：先画 8 方向偏移的深色轮廓
        const off = 1.0;
        final strokePainter = TextPainter(
          text: TextSpan(
            text: a.text,
            style: TextStyle(
              color: const Color(0xcc000000), fontSize: a.fontSize,
              fontWeight: a.bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        for (final dx in [-off, 0.0, off]) {
          for (final dy in [-off, 0.0, off]) {
            strokePainter.paint(canvas, Offset(x + dx, y + dy));
          }
        }
      }
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
