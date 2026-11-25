/// Converts (X)HTML into plain text with Markdown-style headings.
///
/// Deliberately regex based so it copes with malformed HTML as well as the
/// strict XHTML used inside EPUBs.
String htmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  s = s.replaceAll(RegExp(r'<(script|style|head|svg|math|nav)\b[\s\S]*?</\1\s*>', caseSensitive: false), ' ');
  s = s.replaceAllMapped(RegExp(r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1\s*>', caseSensitive: false), (m) {
    final level = int.parse(m[1]!);
    final inner = _stripTags(m[2]!).replaceAll(RegExp(r'\s+'), ' ').trim();
    return inner.isEmpty ? '\n' : '\n\n${'#' * level} $inner\n\n';
  });
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n- ');
  s = s.replaceAll(
    RegExp(
      r'</?(p|div|section|article|blockquote|ul|ol|table|tr|pre|figure|figcaption|dl|dt|dd|aside|header|footer)\b[^>]*>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  s = s.replaceAll(RegExp(r'</?(td|th)\b[^>]*>', caseSensitive: false), ' ');
  s = _stripTags(s);
  s = decodeEntities(s);
  final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim());
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'shy': '',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'bdquo': '„',
  'laquo': '«',
  'raquo': '»',
  'bull': '•',
  'middot': '·',
  'copy': '©',
  'reg': '®',
  'deg': '°',
  'plusmn': '±',
  'times': '×',
  'divide': '÷',
  'micro': 'µ',
  'para': '¶',
  'sect': '§',
  'euro': '€',
  'pound': '£',
  'auml': 'ä',
  'ouml': 'ö',
  'uuml': 'ü',
  'Auml': 'Ä',
  'Ouml': 'Ö',
  'Uuml': 'Ü',
  'szlig': 'ß',
  'eacute': 'é',
  'egrave': 'è',
  'aacute': 'á',
  'agrave': 'à',
  'ccedil': 'ç',
  'ntilde': 'ñ',
  'oacute': 'ó',
  'iacute': 'í',
  'uacute': 'ú',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'pi': 'π',
  'sigma': 'σ',
  'mu': 'μ',
  'lambda': 'λ',
  'rarr': '→',
  'larr': '←',
  'harr': '↔',
  'le': '≤',
  'ge': '≥',
  'ne': '≠',
  'asymp': '≈',
  'infin': '∞',
};

String decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
  final name = m[1]!;
  if (name.startsWith('#x') || name.startsWith('#X')) {
    final code = int.tryParse(name.substring(2), radix: 16);
    return code == null ? m[0]! : String.fromCharCode(code);
  }
  if (name.startsWith('#')) {
    final code = int.tryParse(name.substring(1));
    return code == null ? m[0]! : String.fromCharCode(code);
  }
  return _entities[name] ?? m[0]!;
});
