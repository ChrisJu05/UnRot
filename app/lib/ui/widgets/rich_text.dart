import 'package:material_ui/material_ui.dart';

/// Renders text with `**bold**` and `*italic*` markers as styled spans.
class MarkupText extends StatelessWidget {
  const MarkupText(this.text, {super.key, this.style, this.textAlign = TextAlign.start, this.maxLines});

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;

  static List<InlineSpan> spans(String text, TextStyle base, {Color? accent}) {
    final result = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])');
    var last = 0;
    for (final m in re.allMatches(text)) {
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
    return result;
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
