import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// Minimal PDF object model + tokenizer (ISO 32000-1, section 7.3).
///
/// Values are represented as plain Dart objects:
/// numbers -> [num], booleans -> [bool], null -> `null`, arrays -> [List],
/// dictionaries -> [PdfDict], plus the classes below.
class PdfName {
  const PdfName(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is PdfName && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '/$value';
}

class PdfString {
  const PdfString(this.bytes);
  final Uint8List bytes;

  /// Decodes as a PDF text string (UTF-16BE with BOM, else PDFDocEncoding≈Latin-1).
  String get text {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return latin1.decode(bytes);
  }
}

class PdfRef {
  const PdfRef(this.number, this.generation);
  final int number;
  final int generation;
}

class PdfOperator {
  const PdfOperator(this.name);
  final String name;
}

typedef PdfDict = Map<String, Object?>;

class PdfStream {
  PdfStream(this.dict, this.raw);
  final PdfDict dict;
  final Uint8List raw;
  Uint8List? _decoded;

  /// Applies the stream's filters. [resolve] dereferences indirect values.
  Uint8List decode(Object? Function(Object?) resolve) {
    if (_decoded != null) return _decoded!;
    var data = raw;
    final filter = resolve(dict['Filter']);
    final filters = filter is List ? filter.map(resolve).toList() : [filter];
    final parmsRaw = resolve(dict['DecodeParms']);
    final parmsList = parmsRaw is List ? parmsRaw.map(resolve).toList() : [parmsRaw];
    for (var i = 0; i < filters.length; i++) {
      final f = filters[i];
      if (f is! PdfName) continue;
      final parms = i < parmsList.length && parmsList[i] is Map ? parmsList[i] as PdfDict : null;
      switch (f.value) {
        case 'FlateDecode':
        case 'Fl':
          data = inflateTolerant(data);
          if (parms != null) data = _applyPredictor(data, parms, resolve);
        case 'ASCIIHexDecode':
        case 'AHx':
          data = _asciiHexDecode(data);
        case 'ASCII85Decode':
        case 'A85':
          data = _ascii85Decode(data);
        default:
          // DCT/JPX/CCITT (images) and rare filters are not needed for text.
          return _decoded = Uint8List(0);
      }
    }
    return _decoded = data;
  }
}

class _CollectSink implements Sink<List<int>> {
  final BytesBuilder builder = BytesBuilder(copy: false);
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}

/// Inflates zlib data, returning whatever could be decoded from damaged streams.
Uint8List inflateTolerant(Uint8List data) {
  for (final raw in [false, true]) {
    final sink = _CollectSink();
    final conv = ZLibDecoder(raw: raw).startChunkedConversion(sink);
    try {
      conv.add(data);
      conv.close();
    } catch (_) {
      // Damaged/truncated stream: keep partial output.
    }
    final out = sink.builder.takeBytes();
    if (out.isNotEmpty) return out;
  }
  return Uint8List(0);
}

Uint8List _applyPredictor(Uint8List data, PdfDict parms, Object? Function(Object?) resolve) {
  final predictor = (resolve(parms['Predictor']) as num?)?.toInt() ?? 1;
  if (predictor < 10) return data;
  final colors = (resolve(parms['Colors']) as num?)?.toInt() ?? 1;
  final bpc = (resolve(parms['BitsPerComponent']) as num?)?.toInt() ?? 8;
  final columns = (resolve(parms['Columns']) as num?)?.toInt() ?? 1;
  final bpp = ((colors * bpc) / 8).ceil().clamp(1, 16);
  final rowLength = ((colors * bpc * columns) / 8).ceil();
  final out = BytesBuilder();
  var prev = Uint8List(rowLength);
  for (var pos = 0; pos + rowLength < data.length + 1 && pos < data.length; pos += rowLength + 1) {
    final type = data[pos];
    final row = Uint8List(rowLength);
    for (var i = 0; i < rowLength && pos + 1 + i < data.length; i++) {
      final raw = data[pos + 1 + i];
      final left = i >= bpp ? row[i - bpp] : 0;
      final up = prev[i];
      final upLeft = i >= bpp ? prev[i - bpp] : 0;
      switch (type) {
        case 1:
          row[i] = (raw + left) & 0xff;
        case 2:
          row[i] = (raw + up) & 0xff;
        case 3:
          row[i] = (raw + ((left + up) >> 1)) & 0xff;
        case 4:
          final p = left + up - upLeft;
          final pa = (p - left).abs(), pb = (p - up).abs(), pc = (p - upLeft).abs();
          final pred = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft);
          row[i] = (raw + pred) & 0xff;
        default:
          row[i] = raw;
      }
    }
    out.add(row);
    prev = row;
  }
  return out.takeBytes();
}

Uint8List _asciiHexDecode(Uint8List data) {
  final out = BytesBuilder();
  int? high;
  for (final b in data) {
    if (b == 0x3E) break; // '>'
    final v = _hexValue(b);
    if (v < 0) continue;
    if (high == null) {
      high = v;
    } else {
      out.addByte((high << 4) | v);
      high = null;
    }
  }
  if (high != null) out.addByte(high << 4);
  return out.takeBytes();
}

Uint8List _ascii85Decode(Uint8List data) {
  final out = BytesBuilder();
  final group = <int>[];
  var i = 0;
  if (data.length >= 2 && data[0] == 0x3C && data[1] == 0x7E) i = 2; // <~
  for (; i < data.length; i++) {
    final c = data[i];
    if (c == 0x7E) break; // ~>
    if (c == 0x7A && group.isEmpty) {
      out.add([0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) continue;
    group.add(c - 33);
    if (group.length == 5) {
      var value = 0;
      for (final g in group) {
        value = value * 85 + g;
      }
      out.add([(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]);
      group.clear();
    }
  }
  if (group.isNotEmpty) {
    final n = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var value = 0;
    for (final g in group) {
      value = value * 85 + g;
    }
    final bytes = [(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
    out.add(bytes.sublist(0, n - 1));
  }
  return out.takeBytes();
}

int _hexValue(int b) {
  if (b >= 0x30 && b <= 0x39) return b - 0x30;
  if (b >= 0x41 && b <= 0x46) return b - 0x37;
  if (b >= 0x61 && b <= 0x66) return b - 0x57;
  return -1;
}

bool isPdfWhitespace(int b) => b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 || b == 0x0C || b == 0x00;

bool isPdfDelimiter(int b) =>
    b == 0x28 ||
    b == 0x29 ||
    b == 0x3C ||
    b == 0x3E ||
    b == 0x5B ||
    b == 0x5D ||
    b == 0x7B ||
    b == 0x7D ||
    b == 0x2F ||
    b == 0x25;

/// Tokenizer/parser for PDF objects and content streams.
class PdfLexer {
  PdfLexer(this.data, [this.pos = 0]);

  final Uint8List data;
  int pos;

  bool get atEnd => pos >= data.length;

  void skipWhitespace() {
    while (pos < data.length) {
      final b = data[pos];
      if (isPdfWhitespace(b)) {
        pos++;
      } else if (b == 0x25) {
        // comment
        while (pos < data.length && data[pos] != 0x0A && data[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// Parses the next object. Returns a [PdfOperator] for bare keywords
  /// (content stream operators, `obj`, `stream`, ...). Returns `null` at end
  /// of data or for the `null` keyword.
  Object? next({int depth = 0}) {
    skipWhitespace();
    if (pos >= data.length) return null;
    if (depth > 64) throw const FormatException('PDF object nesting too deep');
    final b = data[pos];
    switch (b) {
      case 0x2F: // '/'
        return _name();
      case 0x28: // '('
        return _literalString();
      case 0x3C: // '<'
        if (pos + 1 < data.length && data[pos + 1] == 0x3C) {
          pos += 2;
          return _dict(depth);
        }
        return _hexString();
      case 0x3E: // '>' stray
        pos++;
        if (pos < data.length && data[pos] == 0x3E) pos++;
        return const PdfOperator('>>');
      case 0x5B: // '['
        pos++;
        final list = <Object?>[];
        while (true) {
          skipWhitespace();
          if (pos >= data.length) break;
          if (data[pos] == 0x5D) {
            pos++;
            break;
          }
          final start = pos;
          final v = next(depth: depth + 1);
          if (pos == start) pos++; // safety
          if (v is PdfOperator) {
            if (v.name == 'R' && list.length >= 2 && list[list.length - 1] is int && list[list.length - 2] is int) {
              final gen = list.removeLast() as int;
              final num = list.removeLast() as int;
              list.add(PdfRef(num, gen));
              continue;
            }
            if (v.name == 'null') {
              list.add(null);
              continue;
            }
            continue;
          }
          list.add(v);
        }
        return list;
      case 0x5D: // ']'
        pos++;
        return const PdfOperator(']');
      case 0x7B:
      case 0x7D:
        pos++;
        return PdfOperator(String.fromCharCode(b));
    }
    if (_isNumberStart(b)) return _number();
    return _keyword();
  }

  static bool _isNumberStart(int b) => (b >= 0x30 && b <= 0x39) || b == 0x2B || b == 0x2D || b == 0x2E;

  Object _number() {
    final start = pos;
    pos++;
    while (pos < data.length) {
      final c = data[pos];
      if ((c >= 0x30 && c <= 0x39) || c == 0x2E) {
        pos++;
      } else {
        break;
      }
    }
    final s = latin1.decode(data.sublist(start, pos));
    if (s.contains('.')) {
      return double.tryParse(s.startsWith('.') || s.startsWith('-.') ? s.replaceFirst('.', '0.') : s) ?? 0.0;
    }
    return int.tryParse(s) ?? 0;
  }

  Object? _keyword() {
    final start = pos;
    while (pos < data.length && !isPdfWhitespace(data[pos]) && !isPdfDelimiter(data[pos])) {
      pos++;
    }
    if (pos == start) {
      pos++;
      return PdfOperator(String.fromCharCode(data[start]));
    }
    final word = latin1.decode(data.sublist(start, pos));
    switch (word) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return const PdfOperator('null');
    }
    return PdfOperator(word);
  }

  PdfName _name() {
    pos++; // '/'
    final bytes = BytesBuilder();
    while (pos < data.length && !isPdfWhitespace(data[pos]) && !isPdfDelimiter(data[pos])) {
      final c = data[pos];
      if (c == 0x23 && pos + 2 < data.length) {
        final h = _hexValue(data[pos + 1]), l = _hexValue(data[pos + 2]);
        if (h >= 0 && l >= 0) {
          bytes.addByte((h << 4) | l);
          pos += 3;
          continue;
        }
      }
      bytes.addByte(c);
      pos++;
    }
    return PdfName(utf8.decode(bytes.takeBytes(), allowMalformed: true));
  }

  PdfString _literalString() {
    pos++; // '('
    final out = BytesBuilder();
    var depth = 1;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x5C) {
        // backslash
        if (pos >= data.length) break;
        final e = data[pos++];
        switch (e) {
          case 0x6E:
            out.addByte(0x0A);
          case 0x72:
            out.addByte(0x0D);
          case 0x74:
            out.addByte(0x09);
          case 0x62:
            out.addByte(0x08);
          case 0x66:
            out.addByte(0x0C);
          case 0x0D:
            if (pos < data.length && data[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var value = e - 0x30;
              for (var k = 0; k < 2 && pos < data.length && data[pos] >= 0x30 && data[pos] <= 0x37; k++) {
                value = value * 8 + (data[pos++] - 0x30);
              }
              out.addByte(value & 0xff);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.addByte(c);
      } else {
        out.addByte(c);
      }
    }
    return PdfString(out.takeBytes());
  }

  PdfString _hexString() {
    pos++; // '<'
    final out = BytesBuilder();
    int? high;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x3E) break;
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high == null) {
        high = v;
      } else {
        out.addByte((high << 4) | v);
        high = null;
      }
    }
    if (high != null) out.addByte(high << 4);
    return PdfString(out.takeBytes());
  }

  PdfDict _dict(int depth) {
    final dict = <String, Object?>{};
    final pending = <Object?>[];
    while (true) {
      skipWhitespace();
      if (pos >= data.length) break;
      if (data[pos] == 0x3E && pos + 1 < data.length && data[pos + 1] == 0x3E) {
        pos += 2;
        break;
      }
      final start = pos;
      final v = next(depth: depth + 1);
      if (pos == start) pos++;
      if (v is PdfOperator) {
        if (v.name == '>>') break;
        if (v.name == 'R' &&
            pending.length >= 3 &&
            pending[pending.length - 1] is int &&
            pending[pending.length - 2] is int) {
          final gen = pending.removeLast() as int;
          final num = pending.removeLast() as int;
          pending.add(PdfRef(num, gen));
        } else if (v.name == 'null') {
          pending.add(null);
        }
      } else {
        pending.add(v);
      }
      // Commit complete key/value pairs whenever we can be sure the value is final
      // (a value followed by a new name key), handled at the end as well.
      while (pending.length >= 4 && pending[0] is PdfName && pending[2] is PdfName && pending[1] is! PdfName) {
        dict[(pending[0] as PdfName).value] = pending[1];
        pending.removeRange(0, 2);
      }
    }
    // Remaining pairs.
    for (var i = 0; i + 1 < pending.length; i += 2) {
      final key = pending[i];
      if (key is PdfName) dict[key.value] = pending[i + 1];
    }
    return dict;
  }
}
