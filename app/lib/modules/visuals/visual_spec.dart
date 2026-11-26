import 'dart:math' as math;

import '../../core/util/json.dart';
import 'expression.dart';

/// Kinds of visuals a reel can show.
const visualKinds = {'function_plot', 'chart', 'diagram', 'equation', 'image'};

/// Interactive control kinds.
const controlKinds = {'slider', 'dial', 'toggle', 'buttons', 'stepper'};

/// Variables that are always available in visual expressions.
const builtinVisualVariables = {'x'};

/// Typed, validated view of a visual reel's data.
///
/// The persisted form is a plain JSON map (see [VisualNormalizer.normalize]);
/// this class just provides convenient accessors for the UI.
class VisualSpec {
  VisualSpec(this.data);

  final Map<String, dynamic> data;

  Map<String, dynamic> get visual => jMap(data['visual']);
  String get kind => jString(visual['kind']);
  String get title => jString(data['title']);
  String get caption => jString(data['caption']);

  // function plot
  double get xMin => jDouble(visual['x_min'], -10);
  double get xMax => jDouble(visual['x_max'], 10);
  double? get yMin => visual['y_min'] is num ? jDouble(visual['y_min']) : null;
  double? get yMax => visual['y_max'] is num ? jDouble(visual['y_max']) : null;
  String get xLabel => jString(visual['x_label']);
  String get yLabel => jString(visual['y_label']);
  List<PlotFunction> get functions => [for (final f in _list(visual['functions'])) PlotFunction(jMap(f))];
  List<PlotPoint> get points => [for (final p in _list(visual['points'])) PlotPoint(jMap(p))];

  // chart
  String get chartType => jString(visual['chart_type'], 'bar');
  List<String> get labels => jStringList(visual['labels']);
  List<ChartSeries> get series => [for (final s in _list(visual['series'])) ChartSeries(jMap(s))];

  // diagram
  String get svg => jString(visual['svg']);

  // equation
  String get latex => jString(visual['latex']);
  List<EquationStep> get steps => [for (final s in _list(visual['steps'])) EquationStep(jMap(s))];

  // image
  String get imageId => jString(visual['image_id']);
  String get imageUrl => jString(visual['image_url']);
  String get alt => jString(visual['alt']);

  List<ControlSpec> get controls => [for (final c in _list(data['controls'])) ControlSpec(jMap(c))];
  AnimationSpec? get animation => data['animate'] is Map ? AnimationSpec(jMap(data['animate'])) : null;
  ChallengeSpec? get challenge => data['challenge'] is Map ? ChallengeSpec(jMap(data['challenge'])) : null;

  /// Initial values of all parameters (controls + animation).
  Map<String, double> initialParams() {
    final values = <String, double>{};
    for (final c in controls) {
      values[c.param] = c.initial;
    }
    final anim = animation;
    if (anim != null) values[anim.param] = anim.from;
    return values;
  }

  static List _list(Object? v) => v is List ? v : const [];
}

class PlotFunction {
  PlotFunction(this.json);
  final Map<String, dynamic> json;
  String get expr => jString(json['expr']);
  String get label => jString(json['label']);
  String get color => jString(json['color']);
  String get visible => jString(json['visible']);
  bool get dashed => jBool(json['dashed']);
}

class PlotPoint {
  PlotPoint(this.json);
  final Map<String, dynamic> json;
  String get x => jString(json['x'], '0');
  String get y => jString(json['y'], '0');
  String get label => jString(json['label']);
  String get visible => jString(json['visible']);
}

class ChartSeries {
  ChartSeries(this.json);
  final Map<String, dynamic> json;
  String get name => jString(json['name']);
  String get color => jString(json['color']);
  List<String> get values => jStringList(json['values']);
}

class EquationStep {
  EquationStep(this.json);
  final Map<String, dynamic> json;
  String get latex => jString(json['latex']);
  String get note => jString(json['note']);
}

class ControlSpec {
  ControlSpec(this.json);
  final Map<String, dynamic> json;
  String get kind => jString(json['kind'], 'slider');
  String get param => jString(json['param']);
  String get label => jString(json['label'], param);
  double get min => jDouble(json['min'], 0);
  double get max => jDouble(json['max'], 1);
  double get step => jDouble(json['step'], 0);
  double get initial => jDouble(json['value'], min);
  String get unit => jString(json['unit']);
  List<(String, double)> get options => [
    for (final o in (json['options'] is List ? json['options'] as List : const []))
      (jString(jMap(o)['label']), jDouble(jMap(o)['value'])),
  ];
}

class AnimationSpec {
  AnimationSpec(this.json);
  final Map<String, dynamic> json;
  String get param => jString(json['param'], 't');
  double get from => jDouble(json['from'], 0);
  double get to => jDouble(json['to'], 1);
  double get seconds => jDouble(json['seconds'], 4).clamp(0.3, 60).toDouble();
  bool get loop => jBool(json['loop'], true);
  bool get autoplay => jBool(json['autoplay'], true);
}

class ChallengeSpec {
  ChallengeSpec(this.json);
  final Map<String, dynamic> json;
  String get prompt => jString(json['prompt']);
  String get condition => jString(json['condition']);
  String get success => jString(json['success']);
}

/// Validates and repairs visual reels produced by an AI (or the offline generator).
class VisualNormalizer {
  static const _maxSvgLength = 30000;

  /// Returns normalized reel data or null when the visual is unusable.
  static Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    // Accept the visual either nested ("visual": {...}) or flattened into the reel.
    final visualRaw = raw['visual'] is Map ? jMap(raw['visual']) : Map<String, dynamic>.of(raw);
    var kind = jString(visualRaw['kind'] ?? visualRaw['visual_type'] ?? raw['kind']).toLowerCase().replaceAll(' ', '_');
    kind = switch (kind) {
      'plot' || 'graph' || 'function' || 'function_graph' => 'function_plot',
      'svg' || 'sketch' || 'drawing' || 'animation' => 'diagram',
      'formula' || 'math' || 'latex' => 'equation',
      'figure' || 'picture' || 'photo' => 'image',
      'bar_chart' || 'line_chart' || 'pie_chart' => 'chart',
      _ => kind,
    };
    if (!visualKinds.contains(kind)) {
      // Infer from the fields present.
      if (visualRaw['functions'] is List) {
        kind = 'function_plot';
      } else if (visualRaw['svg'] is String) {
        kind = 'diagram';
      } else if (visualRaw['series'] is List) {
        kind = 'chart';
      } else if (visualRaw['latex'] is String) {
        kind = 'equation';
      } else if (visualRaw['image_id'] is String || visualRaw['image_url'] is String) {
        kind = 'image';
      } else {
        return null;
      }
    }

    final controls = _controls(raw['controls'] ?? visualRaw['controls']);
    final animRaw = raw['animate'] ?? raw['animation'] ?? visualRaw['animate'] ?? visualRaw['animation'];
    final animate = animRaw is Map ? _animation(jMap(animRaw)) : null;
    final visual = <String, dynamic>{'kind': kind};
    final expressions = <String>[];

    switch (kind) {
      case 'function_plot':
        final functions = <Map<String, dynamic>>[];
        for (final f in (visualRaw['functions'] is List ? visualRaw['functions'] as List : const [])) {
          final m = f is String ? {'expr': f} : jMap(f);
          final expr = _cleanExpr(jString(m['expr'] ?? m['expression'] ?? m['y']));
          if (expr.isEmpty || Expression.tryParse(expr) == null) continue;
          expressions.add(expr);
          final visible = _cleanExpr(jString(m['visible']));
          if (visible.isNotEmpty && Expression.tryParse(visible) != null) expressions.add(visible);
          functions.add({
            'expr': expr,
            'label': jString(m['label']),
            'color': jString(m['color']),
            'visible': Expression.tryParse(visible) == null ? '' : visible,
            'dashed': jBool(m['dashed']),
          });
          if (functions.length >= 6) break;
        }
        if (functions.isEmpty) return null;
        final points = <Map<String, dynamic>>[];
        for (final p in (visualRaw['points'] is List ? visualRaw['points'] as List : const [])) {
          final m = jMap(p);
          final x = _cleanExpr(jString(m['x'], '0')), y = _cleanExpr(jString(m['y'], '0'));
          if (Expression.tryParse(x) == null || Expression.tryParse(y) == null) continue;
          expressions.addAll([x, y]);
          points.add({'x': x, 'y': y, 'label': jString(m['label']), 'visible': _cleanExpr(jString(m['visible']))});
          if (points.length >= 20) break;
        }
        var xMin = jDouble(visualRaw['x_min'], double.nan), xMax = jDouble(visualRaw['x_max'], double.nan);
        final xRange = visualRaw['x_range'];
        if (xRange is List && xRange.length == 2) {
          xMin = jDouble(xRange[0], -10);
          xMax = jDouble(xRange[1], 10);
        }
        if (!xMin.isFinite || !xMax.isFinite || xMin >= xMax) {
          xMin = -10;
          xMax = 10;
        }
        double? yMin = visualRaw['y_min'] is num ? jDouble(visualRaw['y_min']) : null;
        double? yMax = visualRaw['y_max'] is num ? jDouble(visualRaw['y_max']) : null;
        final yRange = visualRaw['y_range'];
        if (yRange is List && yRange.length == 2 && yRange[0] is num && yRange[1] is num) {
          yMin = jDouble(yRange[0]);
          yMax = jDouble(yRange[1]);
        }
        if (yMin != null && yMax != null && yMin >= yMax) yMin = yMax = null;
        visual.addAll({
          'x_min': xMin,
          'x_max': xMax,
          'y_min': yMin,
          'y_max': yMax,
          'x_label': jString(visualRaw['x_label']),
          'y_label': jString(visualRaw['y_label']),
          'functions': functions,
          'points': points,
        });
      case 'chart':
        var type = jString(visualRaw['chart_type'] ?? visualRaw['type'], 'bar').toLowerCase().replaceAll('_chart', '');
        if (!const {'bar', 'line', 'pie'}.contains(type)) type = 'bar';
        final labels = jStringList(visualRaw['labels']).take(24).toList();
        final series = <Map<String, dynamic>>[];
        final rawSeries = visualRaw['series'] is List
            ? visualRaw['series'] as List
            : (visualRaw['values'] is List
                  ? [
                      {'name': '', 'values': visualRaw['values']},
                    ]
                  : const []);
        for (final s in rawSeries) {
          final m = jMap(s);
          final values = <String>[];
          for (final v in (m['values'] is List ? m['values'] as List : const [])) {
            final e = _cleanExpr(v is num ? formatNumber(v.toDouble(), decimals: 6) : jString(v));
            values.add(Expression.tryParse(e) == null ? '0' : e);
          }
          if (values.isEmpty) continue;
          expressions.addAll(values);
          series.add({'name': jString(m['name']), 'color': jString(m['color']), 'values': values.take(24).toList()});
          if (series.length >= 4) break;
        }
        if (series.isEmpty) return null;
        final count = series.map((s) => (s['values'] as List).length).reduce(math.max);
        visual.addAll({
          'chart_type': type,
          'labels': [for (var i = 0; i < count; i++) i < labels.length ? labels[i] : '${i + 1}'],
          'series': series,
          'x_label': jString(visualRaw['x_label']),
          'y_label': jString(visualRaw['y_label']),
        });
      case 'diagram':
        final svg = sanitizeSvg(jString(visualRaw['svg']));
        if (svg == null) return null;
        expressions.addAll(svgExpressions(svg));
        visual['svg'] = svg;
      case 'equation':
        final latex = jString(visualRaw['latex']).trim();
        if (latex.isEmpty) return null;
        final steps = <Map<String, dynamic>>[];
        for (final s in (visualRaw['steps'] is List ? visualRaw['steps'] as List : const [])) {
          final m = s is String ? {'latex': s} : jMap(s);
          if (jString(m['latex']).trim().isEmpty && jString(m['note']).trim().isEmpty) continue;
          steps.add({'latex': jString(m['latex']).trim(), 'note': jString(m['note'] ?? m['explanation']).trim()});
          if (steps.length >= 10) break;
        }
        visual.addAll({'latex': latex, 'steps': steps});
      case 'image':
        final id = jString(visualRaw['image_id'] ?? visualRaw['id'])
            .replaceAll(RegExp(r'[\[\]]'), '')
            .replaceFirst('img:', '');
        final url = jString(visualRaw['image_url'] ?? visualRaw['url']);
        if (id.isEmpty && !url.startsWith('https://')) return null;
        visual.addAll({
          'image_id': id,
          'image_url': url.startsWith('https://') ? url : '',
          'alt': jString(visualRaw['alt']),
        });
    }

    // Challenge: a goal the learner reaches by moving the controls.
    Map<String, dynamic>? challenge;
    final challengeRaw = raw['challenge'] ?? visualRaw['challenge'];
    if (challengeRaw is Map) {
      final c = jMap(challengeRaw);
      final condition = _cleanExpr(jString(c['condition']));
      if (jString(c['prompt']).isNotEmpty && Expression.tryParse(condition) != null) {
        expressions.add(condition);
        challenge = {'prompt': jString(c['prompt']), 'condition': condition, 'success': jString(c['success'])};
      }
    }

    // Every free variable needs a control (or the animation); add sliders for missing ones.
    final declared = {
      ...controls.map((c) => c['param'] as String),
      ?animate?['param'] as String?,
      ...builtinVisualVariables,
    };
    final missing = <String>{};
    for (final e in expressions) {
      final parsed = Expression.tryParse(e);
      if (parsed != null) missing.addAll(parsed.variables.difference(declared));
    }
    for (final name in missing.take(6 - controls.length.clamp(0, 6))) {
      controls.add({
        'kind': 'slider',
        'param': name,
        'label': name,
        'min': -5.0,
        'max': 5.0,
        'step': 0.0,
        'value': 1.0,
        'unit': '',
        'options': const [],
      });
    }

    return {
      'title': jString(raw['title']),
      'caption': jString(raw['caption'] ?? raw['body'] ?? raw['explanation']),
      'visual': visual,
      'controls': controls,
      'animate': animate,
      'challenge': challenge,
    };
  }

  static String _cleanExpr(String e) {
    var s = e.trim();
    // Strip "y =" / "f(x) =" prefixes.
    s = s.replaceFirst(RegExp(r'^\s*(y|[A-Za-z]\([a-z]\))\s*=\s*'), '');
    return s.replaceAll(r'\cdot', '*').replaceAll(r'\pi', 'pi');
  }

  static List<Map<String, dynamic>> _controls(Object? raw) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final c in (raw is List ? raw : const [])) {
      final m = jMap(c);
      final param = jString(m['param'] ?? m['name'] ?? m['variable']).trim();
      if (!RegExp(r'^[A-Za-z_Ͱ-Ͽ][A-Za-z0-9_Ͱ-Ͽ]*$').hasMatch(param) || !seen.add(param)) continue;
      if (Expression.functions.contains(param) || Expression.constants.contains(param) || param == 'x') continue;
      var kind = jString(m['kind'] ?? m['type'], 'slider').toLowerCase();
      if (kind == 'knob' || kind == 'rotary') kind = 'dial';
      if (kind == 'switch' || kind == 'checkbox') kind = 'toggle';
      if (kind == 'segmented' || kind == 'select' || kind == 'radio' || kind == 'button') kind = 'buttons';
      if (!controlKinds.contains(kind)) kind = 'slider';
      var min = jDouble(m['min'], kind == 'toggle' ? 0 : -5);
      var max = jDouble(m['max'], kind == 'toggle' ? 1 : 5);
      if (min > max) (min, max) = (max, min);
      if (min == max) max = min + 1;
      final options = <Map<String, dynamic>>[];
      for (final o in (m['options'] is List ? m['options'] as List : const [])) {
        if (o is num) {
          options.add({'label': formatNumber(o.toDouble()), 'value': o.toDouble()});
        } else {
          final om = jMap(o);
          options.add({
            'label': jString(om['label'], formatNumber(jDouble(om['value']))),
            'value': jDouble(om['value']),
          });
        }
        if (options.length >= 6) break;
      }
      if (kind == 'buttons' && options.isEmpty) kind = 'slider';
      if (kind == 'toggle') {
        min = 0;
        max = 1;
      }
      var value = jDouble(
        m['value'] ?? m['initial'] ?? m['default'],
        kind == 'buttons' ? options.first['value'] as double : min,
      );
      if (kind != 'buttons') value = value.clamp(min, max).toDouble();
      out.add({
        'kind': kind,
        'param': param,
        'label': jString(m['label'], param),
        'min': min,
        'max': max,
        'step': kind == 'stepper' ? math.max(1.0, jDouble(m['step'], 1)) : jDouble(m['step'], 0).abs(),
        'value': value,
        'unit': jString(m['unit']),
        'options': options,
      });
      if (out.length >= 6) break;
    }
    return out;
  }

  static Map<String, dynamic>? _animation(Map<String, dynamic> m) {
    final param = jString(m['param'] ?? m['variable'], 't');
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(param) || param == 'x') return null;
    return {
      'param': param,
      'from': jDouble(m['from'], 0),
      'to': jDouble(m['to'], 1),
      'seconds': jDouble(m['seconds'] ?? m['duration'], 4).clamp(0.3, 60),
      'loop': jBool(m['loop'], true),
      'autoplay': jBool(m['autoplay'], true),
    };
  }

  /// Removes scripts, event handlers, foreign objects and external links.
  /// Returns null if the string is not an SVG document.
  static String? sanitizeSvg(String input) {
    var svg = input.trim();
    final start = svg.indexOf('<svg');
    final end = svg.lastIndexOf('</svg>');
    if (start < 0 || end < start) return null;
    svg = svg.substring(start, end + 6);
    if (svg.length > _maxSvgLength) return null;
    svg = svg.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    svg = svg.replaceAll(RegExp(r'<foreignObject[\s\S]*?</foreignObject>', caseSensitive: false), '');
    svg = svg.replaceAll(RegExp(r'''\son[a-z]+\s*=\s*("[^"]*"|'[^']*')''', caseSensitive: false), '');
    svg = svg.replaceAll(
      RegExp(r'''(xlink:)?href\s*=\s*("|')\s*(https?:|javascript:)[^"']*("|')''', caseSensitive: false),
      '',
    );
    if (!svg.contains('xmlns=')) svg = svg.replaceFirst('<svg', "<svg xmlns='http://www.w3.org/2000/svg'");
    return svg;
  }

  static final _templateRe = RegExp(r'\{\{(.+?)\}\}');

  /// Expressions inside `{{ }}` placeholders of an SVG template.
  static List<String> svgExpressions(String svg) =>
      [for (final m in _templateRe.allMatches(svg)) _cleanExpr(m[1]!)]
          .where((e) => Expression.tryParse(e) != null)
          .toList();

  /// Fills `{{expression}}` placeholders with evaluated numbers.
  static String renderSvgTemplate(String svg, Map<String, double> params) => svg.replaceAllMapped(_templateRe, (m) {
    final v = Expression.eval(_cleanExpr(m[1]!), params);
    return v.isFinite ? formatNumber(v) : '0';
  });
}
