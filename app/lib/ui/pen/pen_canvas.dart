import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/annotation.dart';
import '../../core/models/settings.dart';

enum PenTool { pen, highlighter, eraser }

/// Drawing state shared between a [PenCanvas] and its [PenToolbar].
class PenController extends ChangeNotifier {
  PenController({List<PenStroke>? strokes, Color? color, this.width = 3})
    : _strokes = List.of(strokes ?? const []),
      color = color ?? const Color(0xFFFFD54F);

  final List<PenStroke> _strokes;
  final List<PenStroke> _redo = [];
  PenTool tool = PenTool.pen;
  Color color;
  double width;

  List<PenStroke> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.isEmpty;

  void setTool(PenTool t) {
    tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    if (tool == PenTool.eraser) tool = PenTool.pen;
    notifyListeners();
  }

  void add(PenStroke stroke) {
    _strokes.add(stroke);
    _redo.clear();
    notifyListeners();
  }

  void eraseAt(Offset normalized, double radius) {
    final before = _strokes.length;
    _strokes.removeWhere((s) => s.points.any((p) => (Offset(p.x, p.y) - normalized).distance < radius));
    if (_strokes.length != before) notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _redo.add(_strokes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _strokes.add(_redo.removeLast());
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    _redo.clear();
    notifyListeners();
  }

  void replaceAll(List<PenStroke> strokes) {
    _strokes
      ..clear()
      ..addAll(strokes);
    _redo.clear();
    notifyListeners();
  }
}

/// Pressure-sensitive drawing surface with stylus, eraser and palm rejection support.
///
/// * Stylus (Apple Pencil, S Pen, Wacom/Windows Ink, Linux tablets) always draws
///   when [enabled]; its eraser end or barrel button erases.
/// * Touch and mouse draw only when [acceptFingersAndMouse] is true and the
///   user has not enabled "stylus only" (palm rejection).
/// * Short stylus taps are ignored so buttons below stay usable.
class PenCanvas extends StatefulWidget {
  const PenCanvas({
    super.key,
    required this.controller,
    required this.settings,
    this.enabled = true,
    this.acceptFingersAndMouse = true,
    this.onStrokesChanged,
    this.child,
  });

  final PenController controller;
  final PenSettings settings;
  final bool enabled;
  final bool acceptFingersAndMouse;
  final VoidCallback? onStrokesChanged;
  final Widget? child;

  @override
  State<PenCanvas> createState() => _PenCanvasState();
}

class _PenCanvasState extends State<PenCanvas> {
  final Map<int, _ActiveStroke> _active = {};
  final Set<int> _erasing = {};

  bool _accepts(PointerEvent e) {
    if (!widget.enabled) return false;
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return true;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.mouse:
        return widget.acceptFingersAndMouse && !widget.settings.stylusOnly;
      default:
        return false;
    }
  }

  bool _isEraser(PointerEvent e) =>
      widget.controller.tool == PenTool.eraser ||
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.kind == PointerDeviceKind.stylus && (e.buttons & kPrimaryStylusButton) != 0);

  double _pressure(PointerEvent e) {
    if (!widget.settings.pressureSensitive || e.kind != PointerDeviceKind.stylus) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.05, 1.0);
  }

  Offset _normalize(Offset local, Size size) =>
      Offset(size.width == 0 ? 0 : local.dx / size.width, size.height == 0 ? 0 : local.dy / size.height);

  void _down(PointerDownEvent e, Size size) {
    if (!_accepts(e)) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    if (_isEraser(e)) {
      _erasing.add(e.pointer);
      widget.controller.eraseAt(_normalize(e.localPosition, size), 0.03);
      return;
    }
    final c = widget.controller;
    setState(() {
      _active[e.pointer] = _ActiveStroke(
        kind: e.kind,
        start: DateTime.now(),
        color: c.tool == PenTool.highlighter ? c.color.withValues(alpha: 0.35) : c.color,
        width: c.tool == PenTool.highlighter ? c.width * 4 : c.width,
        tool: c.tool == PenTool.highlighter ? StrokeTool.highlighter : StrokeTool.pen,
      )..add(_normalize(e.localPosition, size), _pressure(e), e.localPosition);
    });
  }

  void _move(PointerMoveEvent e, Size size) {
    if (_erasing.contains(e.pointer)) {
      widget.controller.eraseAt(_normalize(e.localPosition, size), 0.03);
      return;
    }
    final stroke = _active[e.pointer];
    if (stroke == null) return;
    setState(() => stroke.add(_normalize(e.localPosition, size), _pressure(e), e.localPosition));
  }

  void _up(PointerEvent e) {
    if (_erasing.remove(e.pointer)) {
      widget.onStrokesChanged?.call();
      return;
    }
    final stroke = _active.remove(e.pointer);
    if (stroke == null) return;
    final isTap = stroke.length < 4 && DateTime.now().difference(stroke.start).inMilliseconds < 250;
    final isStylus = stroke.kind == PointerDeviceKind.stylus;
    if (!(isTap && isStylus)) {
      widget.controller.add(stroke.toStroke());
      widget.onStrokesChanged?.call();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        Widget canvas = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: (e) => _move(e, size),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) => CustomPaint(
              foregroundPainter: _StrokePainter(
                strokes: widget.controller.strokes,
                active: _active.values.map((a) => a.toStroke()).toList(),
                pressureSensitive: widget.settings.pressureSensitive,
              ),
              child: child,
            ),
            child: widget.child ?? const SizedBox.expand(),
          ),
        );
        if (widget.enabled && widget.acceptFingersAndMouse && !widget.settings.stylusOnly) {
          // Claim vertical drags so drawing with finger/mouse does not scroll the feed.
          canvas = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            child: canvas,
          );
        }
        return canvas;
      },
    );
  }
}

class _ActiveStroke {
  _ActiveStroke({
    required this.kind,
    required this.start,
    required this.color,
    required this.width,
    required this.tool,
  });
  final PointerDeviceKind kind;
  final DateTime start;
  final Color color;
  final double width;
  final StrokeTool tool;
  final List<StrokePoint> points = [];
  double length = 0;
  Offset? _lastLocal;

  void add(Offset normalized, double pressure, Offset local) {
    if (_lastLocal != null) length += (local - _lastLocal!).distance;
    _lastLocal = local;
    points.add(StrokePoint(normalized.dx, normalized.dy, pressure));
  }

  PenStroke toStroke() => PenStroke(points: List.of(points), colorValue: color.toARGB32(), width: width, tool: tool);
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({required this.strokes, required this.active, required this.pressureSensitive});

  final List<PenStroke> strokes;
  final List<PenStroke> active;
  final bool pressureSensitive;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in [...strokes, ...active]) {
      _paintStroke(canvas, size, s);
    }
  }

  void _paintStroke(Canvas canvas, Size size, PenStroke s) {
    if (s.points.isEmpty) return;
    final paint = Paint()
      ..color = Color(s.colorValue)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    Offset at(StrokePoint p) => Offset(p.x * size.width, p.y * size.height);
    double widthAt(double pressure) =>
        s.tool == StrokeTool.highlighter || !pressureSensitive ? s.width : s.width * (0.35 + 1.3 * pressure);
    if (s.points.length == 1) {
      canvas.drawCircle(at(s.points.first), widthAt(s.points.first.pressure) / 2, paint..style = PaintingStyle.fill);
      return;
    }
    for (var i = 1; i < s.points.length; i++) {
      final a = s.points[i - 1], b = s.points[i];
      paint.strokeWidth = math.max(0.6, widthAt((a.pressure + b.pressure) / 2));
      canvas.drawLine(at(a), at(b), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

/// Compact tool palette for a [PenController].
class PenToolbar extends StatelessWidget {
  const PenToolbar({super.key, required this.controller, this.onDone});

  final PenController controller;
  final VoidCallback? onDone;

  static const colors = [Color(0xFFFFD54F), Color(0xFFFFFFFF), Color(0xFFFF6E6E), Color(0xFF69F0AE), Color(0xFF40C4FF)];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Material(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              _toolButton(Icons.edit, PenTool.pen, 'Pen'),
              _toolButton(Icons.border_color, PenTool.highlighter, 'Highlighter'),
              _toolButton(Icons.auto_fix_normal, PenTool.eraser, 'Eraser'),
              for (final c in colors)
                InkWell(
                  onTap: () => controller.setColor(c),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: controller.color.toARGB32() == c.toARGB32() && controller.tool != PenTool.eraser
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo, color: Colors.white),
                onPressed: controller.isEmpty ? null : controller.undo,
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: controller.isEmpty ? null : controller.clear,
              ),
              if (onDone != null)
                IconButton(
                  tooltip: 'Done',
                  icon: const Icon(Icons.check, color: Colors.white),
                  onPressed: onDone,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, PenTool tool, String label) => IconButton(
    tooltip: label,
    isSelected: controller.tool == tool,
    icon: Icon(icon, color: controller.tool == tool ? const Color(0xFFFFD54F) : Colors.white70),
    onPressed: () => controller.setTool(tool),
  );
}
