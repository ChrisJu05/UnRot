import 'package:material_ui/material_ui.dart';

import '../visuals/math_text.dart';

/// Renders text with `**bold**`, `*italic*` and LaTeX math (`$…$`, `$$…$$`).
class MarkupText extends StatelessWidget {
  const MarkupText(this.text, {super.key, this.style, this.textAlign = TextAlign.start, this.maxLines});

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;

  static final _emphasis = RegExp(r'\*\*(.+?)\*\*|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])');

  static List<InlineSpan> spans(String text, TextStyle base, {Color? accent}) {
    final result = <InlineSpan>[];
    for (final segment in splitMath(text)) {
      if (segment.isMath) {
        if (segment.display) {
          result.add(const TextSpan(text: '\n'));
          result.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: MathTex(segment.text, style: base, display: true),
              ),
            ),
          );
          result.add(const TextSpan(text: '\n'));
        } else {
          result.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: MathTex(segment.text, style: base),
            ),
          );
        }
        continue;
      }
      _emphasisSpans(segment.text, accent, result);
    }
    return result;
  }

  static void _emphasisSpans(String text, Color? accent, List<InlineSpan> result) {
    var last = 0;
    for (final m in _emphasis.allMatches(text)) {
      if (m.start > last) result.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(1) != null) {
        result.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(fontWeight: FontWeight.w800, color: accent),
          ),
        );
      } else {
        result.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      last = m.end;
    }
    if (last < text.length) result.add(TextSpan(text: text.substring(last)));
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: base,
        children: spans(text, base, accent: const Color(0xFFFFE082)),
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
