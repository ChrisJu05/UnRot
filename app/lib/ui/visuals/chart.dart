import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../modules/visuals/expression.dart';
import '../../modules/visuals/visual_spec.dart';
import 'plot.dart';

/// Bar, line and pie charts. Values may be expressions of the control parameters.
class ChartView extends StatefulWidget {
  const ChartView({super.key, required this.spec, required this.params});

  final VisualSpec spec;
  final Map<String, double> params;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = [
      for (final s in widget.spec.series) (s, [for (final v in s.values) Expression.eval(v, widget.params)]),
    ];
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
      builder: (context, _) => CustomPaint(
        painter: _ChartPainter(
          type: widget.spec.chartType,
          labels: widget.spec.labels,
          series: series,
          progress: Curves.easeOutCubic.transform(_intro.value),
          yLabel: widget.spec.yLabel,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.type,
    required this.labels,
    required this.series,
    required this.progress,
    required this.yLabel,
  });

  final String type;
  final List<String> labels;
  final List<(ChartSeries, List<double>)> series;
  final double progress;
  final String yLabel;

  static const _small = TextStyle(color: Colors.white70, fontSize: 11);

  TextPainter _tp(String text, TextStyle style, {double maxWidth = 200}) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  Color _color(int i) => parseColor(series[i].$1.color, visualPalette[i % visualPalette.length]);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    if (type == 'pie') {
      _pie(canvas, size);
    } else {
      _axes(canvas, size);
    }
  }

  void _axes(Canvas canvas, Size size) {
    final legendHeight = series.length > 1 || series.first.$1.name.isNotEmpty ? 20.0 : 0.0;
    final rect = Rect.fromLTRB(40, 14 + legendHeight, size.width - 10, size.height - 34);
    final values = [for (final s in series) ...s.$2.where((v) => v.isFinite)];
    if (values.isEmpty || rect.width < 20 || rect.height < 20) return;
    var lo = math.min(0.0, values.reduce(math.min));
    var hi = math.max(0.0, values.reduce(math.max));
    if (hi - lo < 1e-9) hi = lo + 1;
    hi += (hi - lo) * 0.08;
    double py(double v) => rect.bottom - (v - lo) / (hi - lo) * rect.height;

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (final t in niceTicks(lo, hi, target: 5)) {
      canvas.drawLine(Offset(rect.left, py(t)), Offset(rect.right, py(t)), grid);
      final tp = _tp(formatNumber(t), _small);
      tp.paint(canvas, Offset(rect.left - tp.width - 4, py(t) - tp.height / 2));
    }
    canvas.drawLine(
      Offset(rect.left, py(0)),
      Offset(rect.right, py(0)),
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1.2,
    );
    if (yLabel.isNotEmpty) _tp(yLabel, _small).paint(canvas, Offset(rect.left + 4, rect.top - 14));

    final n = labels.length;
    final slot = rect.width / math.max(1, n);
    for (var i = 0; i < n; i++) {
      final tp = _tp(labels[i], _small, maxWidth: math.max(24, slot - 2));
      tp.paint(canvas, Offset(rect.left + slot * (i + 0.5) - tp.width / 2, rect.bottom + 4));
    }

    if (type == 'line') {
      for (var s = 0; s < series.length; s++) {
        final paint = Paint()
          ..color = _color(s)
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke;
        final path = Path();
        var started = false;
        final vals = series[s].$2;
        final visibleCount = (vals.length * progress).ceil();
        for (var i = 0; i < visibleCount && i < vals.length; i++) {
          if (!vals[i].isFinite) continue;
          final p = Offset(rect.left + slot * (i + 0.5), py(vals[i]));
          started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
          started = true;
          canvas.drawCircle(p, 3.5, Paint()..color = _color(s));
        }
        canvas.drawPath(path, paint);
      }
    } else {
      final groupWidth = slot * 0.75;
      final barWidth = groupWidth / series.length;
      for (var s = 0; s < series.length; s++) {
        final vals = series[s].$2;
        for (var i = 0; i < vals.length && i < n; i++) {
          if (!vals[i].isFinite) continue;
          final left = rect.left + slot * i + (slot - groupWidth) / 2 + barWidth * s;
          final top = py(vals[i] * progress), base = py(0);
          final r = Rect.fromLTRB(left + 1, math.min(top, base), left + barWidth - 1, math.max(top, base));
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = _color(s));
          if (progress > 0.95 && barWidth > 18) {
            final tp = _tp(
              formatNumber(vals[i], decimals: 2),
              const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            );
            tp.paint(canvas, Offset(r.center.dx - tp.width / 2, (vals[i] >= 0 ? r.top - tp.height - 1 : r.bottom + 1)));
          }
        }
      }
    }
    _legend(canvas, Offset(rect.left, 4));
  }

  void _legend(Canvas canvas, Offset at) {
    var x = at.dx;
    for (var s = 0; s < series.length; s++) {
      final name = series[s].$1.name;
      if (name.isEmpty) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, at.dy + 3, 12, 12), const Radius.circular(3)),
        Paint()..color = _color(s),
      );
      final tp = _tp(name, const TextStyle(color: Colors.white, fontSize: 12));
      tp.paint(canvas, Offset(x + 16, at.dy + 1));
      x += tp.width + 30;
    }
  }

  void _pie(Canvas canvas, Size size) {
    final vals = series.first.$2.map((v) => v.isFinite && v > 0 ? v : 0.0).toList();
    final total = vals.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final radius = math.min(size.width * 0.5, size.height) / 2 - 8;
    final center = Offset(radius + 10, size.height / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < vals.length; i++) {
      final sweep = vals[i] / total * 2 * math.pi * progress;
      final paint = Paint()..color = visualPalette[i % visualPalette.length];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, true, paint);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()
          ..color = const Color(0x55000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      start += sweep;
    }
    // Legend with percentages.
    var y = center.dy - vals.length * 11.0;
    for (var i = 0; i < vals.length && i < labels.length; i++) {
      final x = center.dx + radius + 18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y + 3, 12, 12), const Radius.circular(3)),
        Paint()..color = visualPalette[i % visualPalette.length],
      );
      final pct = (vals[i] / total * 100).toStringAsFixed(vals[i] / total < 0.1 ? 1 : 0);
      _tp(
        '${labels[i]}  $pct%',
        const TextStyle(color: Colors.white, fontSize: 12),
        maxWidth: size.width - x - 20,
      ).paint(canvas, Offset(x + 18, y));
      y += 22;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
