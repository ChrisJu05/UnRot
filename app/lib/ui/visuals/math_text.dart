import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Repairs LaTeX that lost its backslashes to JSON escapes (\f, \b, \t, \n, \r).
String repairLatex(String latex) => latex
    .replaceAll('\f', r'\f')
    .replaceAll('\b', r'\b')
    .replaceAll('\t', r'\t')
    .replaceAll('\r', r'\r')
    .replaceAllMapped(RegExp(r'\n(?=(u|eq|abla|ot|e|eg|mid|leq|geq|otin|exists)\b)'), (_) => r'\n');

/// Renders a LaTeX formula; falls back to the raw source if it cannot be parsed.
class MathTex extends StatelessWidget {
  const MathTex(this.latex, {super.key, this.style, this.display = false});

  final String latex;
  final TextStyle? style;
  final bool display;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final math = Math.tex(
      repairLatex(latex.trim()),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: base.copyWith(fontWeight: FontWeight.normal),
      onErrorFallback: (_) => Text(latex, style: AppTheme.monoStyle.merge(base)),
    );
    if (!display) return math;
    // Wide formulas scroll horizontally instead of overflowing.
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: math);
  }
}

/// A piece of text that is either plain markup or a math formula.
class MathSegment {
  const MathSegment(this.text, {this.isMath = false, this.display = false});
  final String text;
  final bool isMath;
  final bool display;
}

final _mathRe = RegExp(
  r'\$\$([\s\S]+?)\$\$'
  r'|\\\[([\s\S]+?)\\\]'
  r'|\\\(([\s\S]+?)\\\)'
  r'|(?<![\\$\w])\$(?![\s$])((?:[^$\n\\]|\\.)+?)(?<!\s)\$(?![\d$])',
);

/// Splits text into plain and math segments (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`).
///
/// Prices such as "$5 and $10" are not treated as math.
List<MathSegment> splitMath(String text) {
  final out = <MathSegment>[];
  var last = 0;
  for (final m in _mathRe.allMatches(text)) {
    final display = m[1] != null || m[2] != null;
    final content = (m[1] ?? m[2] ?? m[3] ?? m[4])!;
    // Inline $…$ must look like math (no spaces, or math symbols), not like prose between two prices.
    if (m[4] != null && content.contains(' ') && !RegExp(r'[\\^_=+\-*/<>(){}]').hasMatch(content)) continue;
    if (m.start > last) out.add(MathSegment(text.substring(last, m.start)));
    out.add(MathSegment(content, isMath: true, display: display));
    last = m.end;
  }
  if (last < text.length) out.add(MathSegment(text.substring(last)));
  return out;
}
