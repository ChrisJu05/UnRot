import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../modules/visuals/expression.dart';
import '../../modules/visuals/visual_spec.dart';

/// Builds the widget for one interactive control.
class ParamControl extends StatelessWidget {
  const ParamControl({super.key, required this.spec, required this.value, required this.onChanged});

  final ControlSpec spec;
  final double value;
  final ValueChanged<double> onChanged;

  String get _valueText => '${formatNumber(value, decimals: 2)}${spec.unit.isEmpty ? '' : ' ${spec.unit}'}';

  double _snap(double v) {
    final step = spec.step;
    final snapped = step > 0 ? spec.min + ((v - spec.min) / step).round() * step : v;
    return snapped.clamp(spec.min, spec.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);
    switch (spec.kind) {
      case 'dial':
        return Dial(
          value: value,
          min: spec.min,
          max: spec.max,
          label: spec.label,
          valueText: _valueText,
          onChanged: (v) => onChanged(_snap(v)),
        );
      case 'toggle':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: value >= 0.5, onChanged: (v) => onChanged(v ? 1 : 0)),
            const SizedBox(width: 4),
            Flexible(child: Text(spec.label, style: labelStyle)),
          ],
        );
      case 'buttons':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(spec.label, style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, v) in spec.options)
                  ChoiceChip(label: Text(label), selected: (value - v).abs() < 1e-9, onSelected: (_) => onChanged(v)),
              ],
            ),
          ],
        );
      case 'stepper':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(spec.label, style: labelStyle)),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: value > spec.min ? () => onChanged(_snap(value - spec.step)) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 56,
              child: Text(_valueText, textAlign: TextAlign.center, style: labelStyle.copyWith(fontSize: 18)),
            ),
            IconButton.filledTonal(
              onPressed: value < spec.max ? () => onChanged(_snap(value + spec.step)) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        );
      default:
        final divisions = spec.step > 0 ? ((spec.max - spec.min) / spec.step).round() : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(spec.label, style: labelStyle)),
                Text(_valueText, style: labelStyle.copyWith(color: const Color(0xFFFFD54F))),
              ],
            ),
            SliderTheme(
              data: const SliderThemeData(trackHeight: 5),
              child: Slider(
                value: value.clamp(spec.min, spec.max).toDouble(),
                min: spec.min,
                max: spec.max,
                divisions: divisions != null && divisions > 0 && divisions <= 1000 ? divisions : null,
                onChanged: onChanged,
              ),
            ),
          ],
        );
    }
  }
}

/// A rotary knob: drag around it (or use the mouse wheel) to change the value.
class Dial extends StatelessWidget {
  const Dial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label = '',
    this.valueText = '',
    this.size = 84,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String label;
  final String valueText;
  final double size;

  /// The knob covers 270°, starting at the bottom left.
  static const _sweep = 1.5 * math.pi;
  static const _start = 0.75 * math.pi;

  double get _fraction => max == min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  void _fromPosition(Offset local) {
    final center = Offset(size / 2, size / 2);
    var angle = math.atan2(local.dy - center.dy, local.dx - center.dx); // -pi..pi, 0 = right
    var rel = angle - _start;
    while (rel < 0) {
      rel += 2 * math.pi;
    }
    if (rel > _sweep) {
      // In the dead zone at the bottom: snap to the nearer end.
      rel = rel - _sweep < (2 * math.pi - _sweep) / 2 ? _sweep : 0;
    }
    angle = rel;
    onChanged(min + (max - min) * (angle / _sweep));
  }

  @override
  Widget build(BuildContext context) {
    void drag(DragUpdateDetails d) => _fromPosition(d.localPosition);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // Claim the wheel so the feed does not scroll while turning the dial.
              GestureBinding.instance.pointerSignalResolver.register(event, (e) {
                final dy = (e as PointerScrollEvent).scrollDelta.dy;
                onChanged((value - dy.sign * (max - min) / 50).clamp(min, max).toDouble());
              });
            }
          },
          child: GestureDetector(
            // Vertical + horizontal recognizers win against the feed's swipe.
            onVerticalDragStart: (d) => _fromPosition(d.localPosition),
            onVerticalDragUpdate: drag,
            onHorizontalDragStart: (d) => _fromPosition(d.localPosition),
            onHorizontalDragUpdate: drag,
            onTapDown: (d) => _fromPosition(d.localPosition),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _DialPainter(_fraction)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          valueText,
          style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w800, fontSize: 14),
        ),
        if (label.isNotEmpty)
          SizedBox(
            width: size + 30,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius - 8, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawArc(
      rect,
      Dial._start,
      Dial._sweep,
      false,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      Dial._start,
      Dial._sweep * fraction,
      false,
      Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    final angle = Dial._start + Dial._sweep * fraction;
    final knob = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 16);
    canvas.drawLine(
      center,
      knob,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.fraction != fraction;
}
