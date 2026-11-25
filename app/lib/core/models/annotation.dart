import '../util/json.dart';

/// A single sampled point of a pen stroke.
class StrokePoint {
  const StrokePoint(this.x, this.y, this.pressure);

  /// Coordinates are normalised to 0..1 of the canvas size so annotations
  /// survive window resizes and different screen sizes.
  final double x;
  final double y;

  /// Normalised pressure 0..1 (1.0 for devices without pressure).
  final double pressure;

  List<double> toJson() => [_r(x), _r(y), _r(pressure)];

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  factory StrokePoint.fromJson(Object? json) {
    if (json is List && json.length >= 2) {
      return StrokePoint(jDouble(json[0]), jDouble(json[1]), json.length > 2 ? jDouble(json[2], 1) : 1);
    }
    return const StrokePoint(0, 0, 1);
  }
}

enum StrokeTool { pen, highlighter }

class PenStroke {
  PenStroke({required this.points, required this.colorValue, required this.width, this.tool = StrokeTool.pen});

  final List<StrokePoint> points;
  final int colorValue;

  /// Width in logical pixels at pressure 0.5.
  final double width;
  final StrokeTool tool;

  Map<String, dynamic> toJson() => {
    'c': colorValue,
    'w': width,
    't': tool.name,
    'p': points.map((p) => p.toJson()).toList(),
  };

  factory PenStroke.fromJson(Map<String, dynamic> json) => PenStroke(
    colorValue: jInt(json['c'], 0xFFFFFFFF),
    width: jDouble(json['w'], 3),
    tool: StrokeTool.values.firstWhere((t) => t.name == json['t'], orElse: () => StrokeTool.pen),
    points: (json['p'] is List ? json['p'] as List : const []).map(StrokePoint.fromJson).toList(),
  );
}
