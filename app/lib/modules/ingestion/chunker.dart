import '../../core/models/chunk.dart';

/// Splits extracted text into study-sized sections ([SourceChunk]s).
///
/// * Markdown headings (`#`, `##`, ...) and common heading patterns
///   ("2.1 Cell membranes", "Chapter 3", "KAPITEL 4") start new sections.
/// * Sections are merged or split to land near [targetChars].
/// * Hard-wrapped lines are reflowed and hyphenation at line ends is removed.
class Chunker {
  const Chunker({this.targetChars = 1600, this.minChars = 500, this.maxChars = 2600});

  final int targetChars;
  final int minChars;
  final int maxChars;

  List<SourceChunk> chunk(String sourceId, String text, {String? fallbackTitle}) {
    final blocks = _blocks(normalize(text));
    final sections = <_Section>[];
    final headingStack = <(int, String)>[];
    var current = _Section(const []);

    void closeCurrent() {
      if (current.paragraphs.isNotEmpty) sections.add(current);
    }

    for (final block in blocks) {
      final heading = _heading(block);
      if (heading != null) {
        final (level, title) = heading;
        while (headingStack.isNotEmpty && headingStack.last.$1 >= level) {
          headingStack.removeLast();
        }
        headingStack.add((level, title));
        closeCurrent();
        current = _Section(headingStack.map((h) => h.$2).toList());
        continue;
      }
      current.paragraphs.add(block);
    }
    closeCurrent();

    // Merge tiny sections into the following one (keeps the first heading),
    // split large ones at paragraph/sentence boundaries.
    final sized = <_Section>[];
    for (final s in sections) {
      if (sized.isNotEmpty && sized.last.length < minChars && sized.last.length + s.length <= maxChars) {
        final prev = sized.removeLast();
        final merged = _Section(prev.headingPath.isNotEmpty ? prev.headingPath : s.headingPath)
          ..paragraphs.addAll(prev.paragraphs)
          ..extraTitles.addAll(prev.extraTitles);
        if (s.headingPath.isNotEmpty && s.headingPath.last != merged.headingPath.lastOrNull) {
          merged.extraTitles.add(s.headingPath.last);
          merged.paragraphs.add('## ${s.headingPath.last}');
        }
        merged.paragraphs.addAll(s.paragraphs);
        sized.add(merged);
      } else {
        sized.addAll(_split(s));
      }
    }

    final chunks = <SourceChunk>[];
    var partCounter = 0;
    for (final s in sized) {
      final body = s.paragraphs.join('\n\n').trim();
      if (body.isEmpty) continue;
      String title;
      if (s.headingPath.isNotEmpty) {
        title = s.headingPath.last;
        if (s.part > 0) title = '$title (${s.part + 1})';
      } else {
        partCounter++;
        title = _autoTitle(body) ?? '${fallbackTitle ?? 'Part'} $partCounter';
      }
      chunks.add(
        SourceChunk(
          id: '$sourceId:${chunks.length}',
          sourceId: sourceId,
          index: chunks.length,
          title: title,
          headingPath: s.headingPath,
          text: body,
        ),
      );
    }
    return chunks;
  }

  /// Normalises whitespace, removes hyphenation and reflows hard-wrapped lines.
  static String normalize(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('­', '');
    t = t.replaceAll(RegExp(r'[ \t ]+'), ' ');
    t = t.replaceAll(RegExp(r'[ﬀ]'), 'ff').replaceAll('ﬁ', 'fi').replaceAll('ﬂ', 'fl');
    // "exam-\nple" -> "example" (only when followed by a lowercase letter).
    t = t.replaceAllMapped(RegExp(r'([A-Za-zÀ-ž])-\n\s*([a-zà-ž])'), (m) => '${m[1]}${m[2]}');
    return t.replaceAll(RegExp(r'\n[ ]+'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static final _listItem = RegExp(r'^\s*([-*•▪◦–]|\d{1,3}[.)]|[a-z][.)])\s+');

  List<String> _blocks(String text) {
    final result = <String>[];
    for (final raw in text.split(RegExp(r'\n\s*\n'))) {
      final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      // Headings on their own line inside a block get separated.
      final buffer = <String>[];
      void flush() {
        if (buffer.isNotEmpty) {
          result.add(_reflow(buffer));
          buffer.clear();
        }
      }

      for (final line in lines) {
        if (line.startsWith('#') || (_looksLikeHeading(line) && buffer.isEmpty)) {
          flush();
          result.add(line);
        } else {
          buffer.add(line);
        }
      }
      flush();
    }
    return result;
  }

  /// Joins wrapped lines, keeping list items on separate lines.
  String _reflow(List<String> lines) {
    final out = StringBuffer(lines.first);
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (_listItem.hasMatch(line)) {
        out.write('\n$line');
      } else {
        out.write(' $line');
      }
    }
    return out.toString();
  }

  static final _numbered = RegExp(r'^(\d{1,2}(\.\d{1,2}){0,3})\.?\s+(\S.{1,90})$');
  static final _chapter = RegExp(
    r'^(chapter|kapitel|part|teil|section|abschnitt|lektion|lesson|unit|module|modul|anhang|appendix)\s+[\dIVXLC]+\b.{0,80}$',
    caseSensitive: false,
  );

  bool _looksLikeHeading(String line) {
    if (line.length > 100 || line.length < 3) return false;
    if (RegExp(r'[.!?,;:]$').hasMatch(line) && !_chapter.hasMatch(line)) return false;
    if (_chapter.hasMatch(line)) return true;
    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      final rest = numbered[3]!;
      // "1 kg of flour" is not a heading: require a capitalised word.
      return RegExp(r'^[A-ZÄÖÜ]').hasMatch(rest) && rest.split(' ').length <= 12;
    }
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß]'), '');
    return letters.length >= 4 && letters == letters.toUpperCase() && line.split(' ').length <= 8;
  }

  (int, String)? _heading(String block) {
    if (block.contains('\n')) return null;
    final md = RegExp(r'^(#{1,6})\s+(.+?)\s*#*$').firstMatch(block);
    if (md != null) return (md[1]!.length, md[2]!.trim());
    if (!_looksLikeHeading(block)) return null;
    final numbered = _numbered.firstMatch(block);
    if (numbered != null) return ('.'.allMatches(numbered[1]!.replaceAll(RegExp(r'\.$'), '')).length + 1, block);
    if (_chapter.hasMatch(block)) return (1, block);
    return (2, _titleCase(block));
  }

  static String _titleCase(String s) =>
      s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  Iterable<_Section> _split(_Section s) sync* {
    if (s.length <= maxChars) {
      yield s;
      return;
    }
    var part = 0;
    var current = _Section(s.headingPath, part: part);
    for (final para in s.paragraphs.expand(_splitLongParagraph)) {
      if (current.length > 0 && current.length + para.length > targetChars) {
        yield current;
        current = _Section(s.headingPath, part: ++part);
      }
      current.paragraphs.add(para);
    }
    if (current.paragraphs.isNotEmpty) yield current;
  }

  Iterable<String> _splitLongParagraph(String para) sync* {
    if (para.length <= maxChars) {
      yield para;
      return;
    }
    final sentences = splitSentences(para);
    final buffer = StringBuffer();
    for (final s in sentences) {
      if (buffer.length > 0 && buffer.length + s.length > targetChars) {
        yield buffer.toString().trim();
        buffer.clear();
      }
      buffer.write('$s ');
    }
    if (buffer.length > 0) yield buffer.toString().trim();
  }

  String? _autoTitle(String body) {
    final first = splitSentences(body).firstOrNull;
    if (first == null) return null;
    final words = first.split(' ').take(7).join(' ');
    return words.length < 4 ? null : '${words.replaceAll(RegExp(r'[.,;:!?]+$'), '')}…';
  }
}

class _Section {
  _Section(this.headingPath, {this.part = 0});
  final List<String> headingPath;
  final int part;
  final List<String> paragraphs = [];
  final List<String> extraTitles = [];
  int get length => paragraphs.fold(0, (sum, p) => sum + p.length);
}

/// Splits text into sentences (handles common abbreviations reasonably).
List<String> splitSentences(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  final result = <String>[];
  final re = RegExp(r'(?<=[.!?…])\s+(?=["“„(\[]?[A-ZÄÖÜ0-9])');
  var start = 0;
  for (final m in re.allMatches(normalized)) {
    final candidate = normalized.substring(start, m.start);
    final lastWord = candidate.split(' ').last.toLowerCase();
    if (_abbreviations.contains(lastWord) ||
        RegExp(r'^([a-z]\.){1,3}$').hasMatch(lastWord) ||
        RegExp(r'^\d+\.$').hasMatch(lastWord) && candidate.length < 4) {
      continue;
    }
    result.add(candidate.trim());
    start = m.end;
  }
  result.add(normalized.substring(start).trim());
  return result.where((s) => s.isNotEmpty).toList();
}

const _abbreviations = {
  'e.g.',
  'i.e.',
  'etc.',
  'vs.',
  'dr.',
  'prof.',
  'mr.',
  'mrs.',
  'ms.',
  'fig.',
  'no.',
  'vol.',
  'approx.',
  'ca.',
  'z.b.',
  'bzw.',
  'usw.',
  'vgl.',
  'ggf.',
  'evtl.',
  'd.h.',
  'u.a.',
  'abb.',
  'nr.',
  'bspw.',
  'sog.',
  'st.',
  'jh.',
};
