import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../modules/visuals/expression.dart';
import '../../modules/visuals/visual_spec.dart';

const visualPalette = [
  Color(0xFFFFD54F),
  Color(0xFF80DEEA),
  Color(0xFFFF8A80),
  Color(0xFFB39DDB),
  Color(0xFFA5D6A7),
  Color(0xFFFFAB91),
];

const _namedColors = {
  'red': Color(0xFFFF8A80),
  'blue': Color(0xFF82B1FF),
  'green': Color(0xFFA5D6A7),
  'yellow': Color(0xFFFFD54F),
  'orange': Color(0xFFFFAB40),
  'purple': Color(0xFFB39DDB),
  'pink': Color(0xFFF48FB1),
  'cyan': Color(0xFF80DEEA),
  'teal': Color(0xFF80CBC4),
  'white': Color(0xFFFFFFFF),
  'gray': Color(0xFFBDBDBD),
  'grey': Color(0xFFBDBDBD),
};

/// Parses `#RRGGBB`, `#AARRGGBB`, `#RGB` or a basic colour name.
Color parseColor(String value, Color fallback) {
  final v = value.trim().toLowerCase();
  if (_namedColors.containsKey(v)) return _namedColors[v]!;
  var hex = v.startsWith('#') ? v.substring(1) : v;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'ff$hex';
  final parsed = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
  return parsed == null ? fallback : Color(parsed);
}

/// "Nice" axis ticks (1, 2, 5 × 10^n steps).
List<double> niceTicks(double min, double max, {int target = 6}) {
  if (!min.isFinite || !max.isFinite || max <= min) return const [];
  final raw = (max - min) / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step =
      (norm < 1.5
          ? 1
          : norm < 3
          ? 2
          : norm < 7
          ? 5
          : 10) *
      mag;
  final ticks = <double>[];
  for (var t = (min / step).ceil() * step; t <= max + step * 1e-9; t += step) {
    ticks.add((t / step).round() * step);
    if (ticks.length > 50) break;
  }
  return ticks;
}

bool _visible(String condition, Map<String, double> vars) =>
    condition.isEmpty || (Expression.tryParse(condition)?.eval(vars) ?? 1) != 0;

/// Interactive plot of y = f(x) functions with points, legend and a readout.
class FunctionPlot extends StatefulWidget {
  const FunctionPlot({super.key, required this.spec, required this.params});

  final VisualSpec spec;
  final Map<String, double> params;

  @override
  State<FunctionPlot> createState() => _FunctionPlotState();
}

class _FunctionPlotState extends State<FunctionPlot> {
  double? _cursorX;

  void _setCursor(Offset local, Size size) {
    final rect = _PlotPainter.plotRect(size);
    final t = ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    setState(() => _cursorX = widget.spec.xMin + t * (widget.spec.xMax - widget.spec.xMin));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _setCursor(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _setCursor(d.localPosition, size),
          onDoubleTap: () => setState(() => _cursorX = null),
          child: CustomPaint(
            size: size,
            painter: _PlotPainter(spec: widget.spec, params: widget.params, cursorX: _cursorX),
          ),
        );
      },
    );
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({required this.spec, required this.params, this.cursorX});

  final VisualSpec spec;
  final Map<String, double> params;
  final double? cursorX;

  static Rect plotRect(Size size) => Rect.fromLTRB(40, 12, size.width - 12, size.height - 28);

  static const _labelStyle = TextStyle(color: Colors.white70, fontSize: 11);

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    TextStyle style = _labelStyle,
    Alignment align = Alignment.topLeft,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = at.dx - tp.width * (align.x + 1) / 2;
    final dy = at.dy - tp.height * (align.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = plotRect(size);
    if (rect.width <= 10 || rect.height <= 10) return;
    final xMin = spec.xMin, xMax = spec.xMax;
    final functions = spec.functions.where((f) => _visible(f.visible, params)).toList();
    final samples = rect.width.clamp(120, 700).round();

    // Sample all functions.
    final series = <List<double>>[];
    final vars = Map<String, double>.of(params);
    for (final f in functions) {
      final expr = Expression.tryParse(f.expr);
      final ys = <double>[];
      for (var i = 0; i <= samples; i++) {
        vars['x'] = xMin + (xMax - xMin) * i / samples;
        ys.add(expr?.eval(vars) ?? double.nan);
      }
      series.add(ys);
    }
    final points = <(double, double, String)>[];
    for (final p in spec.points) {
      if (!_visible(p.visible, params)) continue;
      final px = Expression.eval(p.x, params), py = Expression.eval(p.y, params);
      if (px.isFinite && py.isFinite) points.add((px, py, p.label));
    }

    // Y range: explicit or robust automatic range.
    var yMin = spec.yMin, yMax = spec.yMax;
    if (yMin == null || yMax == null) {
      final values = [
        for (final s in series) ...s.where((v) => v.isFinite && v.abs() < 1e6),
        for (final p in points) p.$2,
      ]..sort();
      if (values.isEmpty) {
        yMin = -1;
        yMax = 1;
      } else {
        var lo = values[(values.length * 0.02).floor()];
        var hi = values[((values.length - 1) * 0.98).ceil()];
        if (hi - lo < 1e-9) {
          lo -= 1;
          hi += 1;
        }
        final pad = (hi - lo) * 0.1;
        yMin = spec.yMin ?? lo - pad;
        yMax = spec.yMax ?? hi + pad;
      }
    }
    final y0 = yMin, y1 = yMax;
    double px(double x) => rect.left + (x - xMin) / (xMax - xMin) * rect.width;
    double py(double y) => rect.bottom - (y - y0) / (y1 - y0) * rect.height;

    // Background, grid and tick labels.
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = const Color(0x22000000));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (final t in niceTicks(xMin, xMax)) {
      canvas.drawLine(Offset(px(t), rect.top), Offset(px(t), rect.bottom), grid);
      _text(canvas, formatNumber(t), Offset(px(t), rect.bottom + 4), align: Alignment.topCenter);
    }
    for (final t in niceTicks(y0, y1, target: 5)) {
      canvas.drawLine(Offset(rect.left, py(t)), Offset(rect.right, py(t)), grid);
      _text(canvas, formatNumber(t), Offset(rect.left - 4, py(t)), align: Alignment.centerRight);
    }
    final axis = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    if (y0 <= 0 && y1 >= 0) canvas.drawLine(Offset(rect.left, py(0)), Offset(rect.right, py(0)), axis);
    if (xMin <= 0 && xMax >= 0) canvas.drawLine(Offset(px(0), rect.top), Offset(px(0), rect.bottom), axis);
    if (spec.xLabel.isNotEmpty) {
      _text(canvas, spec.xLabel, Offset(rect.right - 2, rect.bottom - 4), align: Alignment.bottomRight);
    }
    if (spec.yLabel.isNotEmpty) _text(canvas, spec.yLabel, Offset(rect.left + 4, rect.top + 2));

    canvas.save();
    canvas.clipRect(rect);
    for (var k = 0; k < functions.length; k++) {
      final color = parseColor(functions[k].color, visualPalette[k % visualPalette.length]);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var penDown = false;
      double? lastY;
      for (var i = 0; i <= samples; i++) {
        final y = series[k][i];
        if (!y.isFinite) {
          penDown = false;
          continue;
        }
        final x = xMin + (xMax - xMin) * i / samples;
        final sy = py(y).clamp(rect.top - rect.height * 2, rect.bottom + rect.height * 2).toDouble();
        // Break the line at discontinuities (e.g. tan(x), 1/x).
        if (penDown && lastY != null && (sy - lastY).abs() > rect.height * 1.5) penDown = false;
        if (penDown) {
          path.lineTo(px(x), sy);
        } else {
          path.moveTo(px(x), sy);
          penDown = true;
        }
        lastY = sy;
      }
      if (functions[k].dashed) {
        for (final metric in path.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 12) {
            canvas.drawPath(metric.extractPath(d, math.min(d + 7, metric.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }
    for (final p in points) {
      final at = Offset(px(p.$1), py(p.$2));
      canvas.drawCircle(at, 6, Paint()..color = Colors.white);
      canvas.drawCircle(at, 4, Paint()..color = const Color(0xFFFF8A80));
      if (p.$3.isNotEmpty) {
        _text(
          canvas,
          p.$3,
          at + const Offset(8, -8),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          align: Alignment.bottomLeft,
        );
      }
    }
    canvas.restore();

    // Legend.
    var ly = rect.top + 8;
    for (var k = 0; k < functions.length; k++) {
      final label = functions[k].label.replaceAll(r'$', '');
      if (label.isEmpty) continue;
      final color = parseColor(functions[k].color, visualPalette[k % visualPalette.length]);
      canvas.drawLine(
        Offset(rect.left + 8, ly + 7),
        Offset(rect.left + 24, ly + 7),
        Paint()
          ..color = color
          ..strokeWidth = 3,
      );
      _text(
        canvas,
        label,
        Offset(rect.left + 30, ly),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      );
      ly += 18;
    }

    // Readout at the tapped x position.
    final cx = cursorX;
    if (cx != null) {
      final x = px(cx);
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 1,
      );
      final readout = StringBuffer('x = ${formatNumber(cx, decimals: 2)}');
      final v = Map<String, double>.of(params)..['x'] = cx;
      for (var k = 0; k < functions.length; k++) {
        final y = Expression.eval(functions[k].expr, v);
        if (!y.isFinite) continue;
        final color = parseColor(functions[k].color, visualPalette[k % visualPalette.length]);
        canvas.drawCircle(Offset(x, py(y)), 5, Paint()..color = color);
        readout.write(
          '   ${functions[k].label.isEmpty ? 'y' : functions[k].label.replaceAll(r'$', '')} = ${formatNumber(y, decimals: 2)}',
        );
      }
      _text(
        canvas,
        readout.toString(),
        Offset(rect.right - 6, rect.top + 6),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0x99000000),
        ),
        align: Alignment.topRight,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlotPainter old) => true;
}
