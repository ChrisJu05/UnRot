import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'pdf_fonts.dart';
import 'pdf_objects.dart';

class PdfEncryptedException implements Exception {}

/// A line of text on a page with its (device space) font size.
class PdfTextLine {
  PdfTextLine(this.fontSize, {this.gapBefore = 0});
  final StringBuffer text = StringBuffer();
  double fontSize;

  /// Vertical distance to the previous line in multiples of font size.
  final double gapBefore;
}

class PdfPageText {
  PdfPageText(this.lines);
  final List<PdfTextLine> lines;
}

/// Parses a PDF file and extracts text page by page.
///
/// Supports classic xref tables, cross-reference/object streams (PDF 1.5+),
/// Flate/ASCIIHex/ASCII85 filters, ToUnicode CMaps, simple font encodings with
/// /Differences, form XObjects and inline images. Encrypted files are reported
/// via [PdfEncryptedException].
class PdfDocumentParser {
  PdfDocumentParser(this.bytes);

  final Uint8List bytes;
  final Map<int, Object?> _objects = {};
  final Map<String, PdfFont> _fontCache = {};
  final List<PdfDict> _trailers = [];
  bool unmappedFonts = false;

  Object? resolve(Object? value, [int depth = 0]) {
    var v = value;
    var d = depth;
    while (v is PdfRef && d < 32) {
      v = _objects[v.number];
      d++;
    }
    return v;
  }

  void _parseObjects() {
    final text = latin1.decode(bytes);
    final objRe = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    var searchFrom = 0;
    while (true) {
      final match = objRe.allMatches(text, searchFrom).firstOrNull;
      if (match == null) break;
      final number = int.parse(match[1]!);
      final lexer = PdfLexer(bytes, match.end);
      Object? value;
      try {
        value = lexer.next();
        if (value is PdfOperator && value.name == 'null') value = null;
      } catch (_) {
        searchFrom = match.end;
        continue;
      }
      lexer.skipWhitespace();
      var end = lexer.pos;
      if (value is Map && _startsWith(lexer.pos, 'stream')) {
        var start = lexer.pos + 6;
        if (start < bytes.length && bytes[start] == 0x0D) start++;
        if (start < bytes.length && bytes[start] == 0x0A) start++;
        final dict = value as PdfDict;
        final lengthValue = resolve(dict['Length']);
        int? streamEnd;
        if (lengthValue is int && lengthValue >= 0 && start + lengthValue <= bytes.length) {
          var k = start + lengthValue;
          while (k < bytes.length && isPdfWhitespace(bytes[k])) {
            k++;
          }
          if (_startsWith(k, 'endstream')) streamEnd = start + lengthValue;
        }
        if (streamEnd == null) {
          final idx = text.indexOf('endstream', start);
          streamEnd = idx < 0 ? bytes.length : idx;
          // Trim the EOL that precedes `endstream`.
          while (streamEnd! > start && (bytes[streamEnd - 1] == 0x0A || bytes[streamEnd - 1] == 0x0D)) {
            streamEnd--;
          }
        }
        value = PdfStream(dict, Uint8List.sublistView(bytes, start, streamEnd));
        end = streamEnd;
      }
      _objects[number] = value;
      if (value is PdfStream && (value.dict['Type'] as PdfName?)?.value == 'XRef') _trailers.add(value.dict);
      searchFrom = math.max(end, match.end);
    }

    // Classic trailers.
    final trailerRe = RegExp(r'trailer\s*<<');
    for (final m in trailerRe.allMatches(text)) {
      try {
        final dict = PdfLexer(bytes, m.end - 2).next();
        if (dict is Map) _trailers.add(dict as PdfDict);
      } catch (_) {}
    }

    // Objects inside object streams (PDF 1.5+).
    for (final entry in _objects.entries.toList()) {
      final stream = entry.value;
      if (stream is! PdfStream || (resolve(stream.dict['Type']) as PdfName?)?.value != 'ObjStm') continue;
      try {
        final data = stream.decode(resolve);
        final n = (resolve(stream.dict['N']) as num?)?.toInt() ?? 0;
        final first = (resolve(stream.dict['First']) as num?)?.toInt() ?? 0;
        final header = PdfLexer(data);
        final pairs = <(int, int)>[];
        for (var i = 0; i < n; i++) {
          final objNum = header.next(), offset = header.next();
          if (objNum is int && offset is int) pairs.add((objNum, offset));
        }
        for (final (objNum, offset) in pairs) {
          if (_objects.containsKey(objNum) && _objects[objNum] != null) continue;
          if (first + offset >= data.length) continue;
          var v = PdfLexer(data, first + offset).next();
          if (v is PdfOperator) v = null;
          _objects[objNum] = v;
        }
      } catch (_) {}
    }
  }

  bool _startsWith(int pos, String keyword) {
    if (pos + keyword.length > bytes.length) return false;
    for (var i = 0; i < keyword.length; i++) {
      if (bytes[pos + i] != keyword.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Extracts all pages. Throws [PdfEncryptedException] for encrypted files.
  List<PdfPageText> extractPages() {
    _parseObjects();
    for (final t in _trailers) {
      if (t.containsKey('Encrypt')) throw PdfEncryptedException();
    }
    PdfDict? catalog;
    for (final t in _trailers.reversed) {
      final root = resolve(t['Root']);
      if (root is Map) {
        catalog = root as PdfDict;
        break;
      }
    }
    catalog ??= _objects.values
        .whereType<Map>()
        .cast<PdfDict>()
        .where((d) => (d['Type'] as PdfName?)?.value == 'Catalog')
        .firstOrNull;

    final pages = <(PdfDict page, PdfDict? resources)>[];
    final visited = <Object>{};
    void walk(Object? node, PdfDict? inheritedResources, int depth) {
      final dict = resolve(node);
      if (dict is! Map || depth > 64 || !visited.add(dict)) return;
      final d = dict as PdfDict;
      final res = resolve(d['Resources']);
      final resources = res is Map ? res as PdfDict : inheritedResources;
      final kids = resolve(d['Kids']);
      final type = (resolve(d['Type']) as PdfName?)?.value;
      if (kids is List && type != 'Page') {
        for (final kid in kids) {
          walk(kid, resources, depth + 1);
        }
      } else if (type == 'Page' || d.containsKey('Contents')) {
        pages.add((d, resources));
      }
    }

    if (catalog != null) walk(catalog['Pages'], null, 0);
    if (pages.isEmpty) {
      // Fallback: every page-like object in file order.
      for (final obj in _objects.values) {
        if (obj is Map && (obj['Type'] as PdfName?)?.value == 'Page') {
          final res = resolve(obj['Resources']);
          pages.add((obj as PdfDict, res is Map ? res as PdfDict : null));
        }
      }
    }

    final result = <PdfPageText>[];
    for (final (page, resources) in pages) {
      final contents = resolve(page['Contents']);
      final streams = contents is List
          ? contents.map(resolve).whereType<PdfStream>().toList()
          : [if (contents is PdfStream) contents];
      final builder = BytesBuilder(copy: false);
      for (final s in streams) {
        builder.add(s.decode(resolve));
        builder.addByte(0x0A);
      }
      final interpreter = _ContentInterpreter(this);
      try {
        interpreter.run(builder.takeBytes(), resources, 0);
      } catch (_) {
        // Keep whatever was extracted from a damaged page.
      }
      result.add(PdfPageText(interpreter.lines.where((l) => l.text.toString().trim().isNotEmpty).toList()));
    }
    return result;
  }

  PdfFont fontFor(Object? fontRef, PdfDict? fontDict) {
    final key = fontRef is PdfRef ? 'r${fontRef.number}' : 'd${identityHashCode(fontDict)}';
    return _fontCache.putIfAbsent(key, () {
      if (fontDict == null) return PdfFont.fallback();
      try {
        final font = PdfFont.fromDict(fontDict, resolve);
        if (font.lacksUnicode) unmappedFonts = true;
        return font;
      } catch (_) {
        return PdfFont.fallback();
      }
    });
  }
}

/// 2D affine matrix [a b c d e f].
class _M {
  const _M(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _M(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  /// this × other (apply this, then other).
  _M times(_M o) => _M(
    a * o.a + b * o.c,
    a * o.b + b * o.d,
    c * o.a + d * o.c,
    c * o.b + d * o.d,
    e * o.a + f * o.c + o.e,
    e * o.b + f * o.d + o.f,
  );

  (double, double) apply(double x, double y) => (a * x + c * y + e, b * x + d * y + f);
}

class _ContentInterpreter {
  _ContentInterpreter(this.doc);

  final PdfDocumentParser doc;
  final List<PdfTextLine> lines = [];

  _M ctm = _M.identity;
  final List<_M> ctmStack = [];
  _M tm = _M.identity;
  _M tlm = _M.identity;
  PdfFont font = PdfFont.fallback();
  double fontSize = 10;
  double charSpacing = 0;
  double wordSpacing = 0;
  double hScale = 1;
  double leading = 0;

  double? lastX;
  double? lastY;
  double lastSize = 10;

  double _num(Object? v) => v is num ? v.toDouble() : 0;

  void run(Uint8List data, PdfDict? resources, int depth) {
    if (depth > 6) return;
    final lexer = PdfLexer(data);
    final operands = <Object?>[];
    final fonts = resources == null ? null : doc.resolve(resources['Font']);
    final xobjects = resources == null ? null : doc.resolve(resources['XObject']);
    var iterations = 0;
    while (!lexer.atEnd && iterations++ < 5000000) {
      final start = lexer.pos;
      final token = lexer.next();
      if (lexer.pos == start) {
        lexer.pos++;
        continue;
      }
      if (token is! PdfOperator) {
        operands.add(token);
        if (operands.length > 64) operands.removeAt(0);
        continue;
      }
      final op = token.name;
      switch (op) {
        case 'BT':
          tm = _M.identity;
          tlm = _M.identity;
        case 'Tf':
          if (operands.length >= 2) {
            fontSize = _num(operands[operands.length - 1]);
            final name = operands[operands.length - 2];
            if (name is PdfName && fonts is Map) {
              final ref = fonts[name.value];
              final dict = doc.resolve(ref);
              font = doc.fontFor(ref, dict is Map ? dict as PdfDict : null);
            }
          }
        case 'Td':
          if (operands.length >= 2) _td(_num(operands[operands.length - 2]), _num(operands[operands.length - 1]));
        case 'TD':
          if (operands.length >= 2) {
            leading = -_num(operands[operands.length - 1]);
            _td(_num(operands[operands.length - 2]), _num(operands[operands.length - 1]));
          }
        case 'Tm':
          if (operands.length >= 6) {
            final o = operands.sublist(operands.length - 6).map(_num).toList();
            tm = tlm = _M(o[0], o[1], o[2], o[3], o[4], o[5]);
          }
        case 'T*':
          _td(0, -leading);
        case 'Tc':
          if (operands.isNotEmpty) charSpacing = _num(operands.last);
        case 'Tw':
          if (operands.isNotEmpty) wordSpacing = _num(operands.last);
        case 'Tz':
          if (operands.isNotEmpty) hScale = _num(operands.last) / 100;
        case 'TL':
          if (operands.isNotEmpty) leading = _num(operands.last);
        case 'Tj':
          if (operands.isNotEmpty && operands.last is PdfString) _show((operands.last as PdfString).bytes);
        case "'":
          _td(0, -leading);
          if (operands.isNotEmpty && operands.last is PdfString) _show((operands.last as PdfString).bytes);
        case '"':
          if (operands.length >= 3) {
            wordSpacing = _num(operands[operands.length - 3]);
            charSpacing = _num(operands[operands.length - 2]);
          }
          _td(0, -leading);
          if (operands.isNotEmpty && operands.last is PdfString) _show((operands.last as PdfString).bytes);
        case 'TJ':
          if (operands.isNotEmpty && operands.last is List) {
            for (final item in operands.last as List) {
              if (item is PdfString) {
                _show(item.bytes);
              } else if (item is num) {
                final shift = -item.toDouble() / 1000 * fontSize * hScale;
                if (item < -180 && lines.isNotEmpty && !_endsWithSpace()) lines.last.text.write(' ');
                tm = _M(1, 0, 0, 1, shift, 0).times(tm);
                _updateLast();
              }
            }
          }
        case 'q':
          ctmStack.add(ctm);
        case 'Q':
          if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
        case 'cm':
          if (operands.length >= 6) {
            final o = operands.sublist(operands.length - 6).map(_num).toList();
            ctm = _M(o[0], o[1], o[2], o[3], o[4], o[5]).times(ctm);
          }
        case 'Do':
          if (operands.isNotEmpty && operands.last is PdfName && xobjects is Map) {
            final xo = doc.resolve(xobjects[(operands.last as PdfName).value]);
            if (xo is PdfStream && (doc.resolve(xo.dict['Subtype']) as PdfName?)?.value == 'Form') {
              final saved = (ctm, tm, tlm, font, fontSize);
              final matrix = doc.resolve(xo.dict['Matrix']);
              if (matrix is List && matrix.length == 6) {
                final o = matrix.map((e) => _num(doc.resolve(e))).toList();
                ctm = _M(o[0], o[1], o[2], o[3], o[4], o[5]).times(ctm);
              }
              final res = doc.resolve(xo.dict['Resources']);
              run(xo.decode(doc.resolve), res is Map ? res as PdfDict : resources, depth + 1);
              ctm = saved.$1;
              tm = saved.$2;
              tlm = saved.$3;
              font = saved.$4;
              fontSize = saved.$5;
            }
          }
        case 'BI':
          _skipInlineImage(lexer);
      }
      operands.clear();
    }
  }

  void _skipInlineImage(PdfLexer lexer) {
    // Skip the image dictionary up to `ID`, then binary data up to `EI`.
    while (!lexer.atEnd) {
      final t = lexer.next();
      if (t is PdfOperator && t.name == 'ID') break;
    }
    final data = lexer.data;
    var i = lexer.pos + 1;
    while (i + 2 < data.length) {
      if (data[i] == 0x45 &&
          data[i + 1] == 0x49 &&
          isPdfWhitespace(data[i - 1]) &&
          (i + 2 >= data.length || isPdfWhitespace(data[i + 2]) || isPdfDelimiter(data[i + 2]))) {
        lexer.pos = i + 2;
        return;
      }
      i++;
    }
    lexer.pos = data.length;
  }

  void _td(double tx, double ty) {
    tlm = _M(1, 0, 0, 1, tx, ty).times(tlm);
    tm = tlm;
  }

  bool _endsWithSpace() {
    final s = lines.last.text;
    if (s.isEmpty) return true;
    final str = s.toString();
    return str.endsWith(' ');
  }

  (double, double, double) _devicePosition() {
    final m = tm.times(ctm);
    final scale = math.sqrt(m.c * m.c + m.d * m.d);
    return (m.e, m.f, (fontSize * scale).abs());
  }

  void _updateLast() {
    final (x, y, _) = _devicePosition();
    lastX = x;
    lastY = y;
  }

  void _show(Uint8List bytes) {
    final glyphs = font.decode(bytes);
    if (glyphs.isEmpty) return;
    final (x, y, size) = _devicePosition();
    final effectiveSize = size < 0.5 ? 10.0 : size;
    if (lines.isEmpty || lastY == null) {
      lines.add(PdfTextLine(effectiveSize));
    } else {
      final dy = (y - lastY!).abs();
      final ref = math.max(effectiveSize, lastSize);
      if (dy > ref * 0.55) {
        lines.add(PdfTextLine(effectiveSize, gapBefore: dy / ref));
      } else {
        final dx = x - lastX!;
        if ((dx > effectiveSize * 0.22 || dx < -effectiveSize * 2) && !_endsWithSpace()) {
          lines.last.text.write(' ');
        }
      }
    }
    final line = lines.last;
    if (effectiveSize > line.fontSize && line.text.isEmpty) line.fontSize = effectiveSize;
    for (final g in glyphs) {
      line.text.write(g.text);
      final advance = (g.width / 1000 * fontSize + charSpacing + (g.isSpaceCode ? wordSpacing : 0)) * hScale;
      tm = _M(1, 0, 0, 1, advance, 0).times(tm);
    }
    _updateLast();
    lastSize = effectiveSize;
  }
}
