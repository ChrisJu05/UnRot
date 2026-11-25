import 'dart:convert';
import 'dart:typed_data';

import 'pdf_objects.dart';

/// A decoded glyph: the Unicode text it represents and its advance width
/// (in 1/1000 text space units).
class PdfGlyph {
  const PdfGlyph(this.text, this.width, this.isSpaceCode);
  final String text;
  final double width;

  /// True for single-byte code 32 (receives word spacing `Tw`).
  final bool isSpaceCode;
}

/// Font information needed to turn string bytes into Unicode text.
class PdfFont {
  PdfFont._({
    required this.isComposite,
    required this.toUnicode,
    required this.codespace,
    required this.encoding,
    required this.widths,
    required this.defaultWidth,
    required this.widthScale,
    required this.isBuiltinTeX,
  });

  final bool isComposite;
  final Map<int, String>? toUnicode;
  final List<PdfCodespaceRange> codespace;
  final List<String?>? encoding;
  final Map<int, double> widths;
  final double defaultWidth;
  final double widthScale;
  final bool isBuiltinTeX;

  /// True when text could not be mapped to Unicode reliably.
  bool get lacksUnicode => isComposite && toUnicode == null;

  static PdfFont fallback() => PdfFont._(
    isComposite: false,
    toUnicode: null,
    codespace: const [],
    encoding: _standardEncoding(),
    widths: const {},
    defaultWidth: 500,
    widthScale: 1,
    isBuiltinTeX: false,
  );

  factory PdfFont.fromDict(PdfDict dict, Object? Function(Object?) resolve) {
    final subtype = (resolve(dict['Subtype']) as PdfName?)?.value ?? 'Type1';
    final isComposite = subtype == 'Type0';
    Map<int, String>? toUnicode;
    var codespace = <PdfCodespaceRange>[];
    final tu = resolve(dict['ToUnicode']);
    if (tu is PdfStream) {
      final cmap = _parseCMap(tu.decode(resolve));
      if (cmap.map.isNotEmpty) toUnicode = cmap.map;
      codespace = cmap.codespace;
    }
    if (codespace.isEmpty) {
      codespace = isComposite ? [const PdfCodespaceRange(2, 0, 0xffff)] : [const PdfCodespaceRange(1, 0, 0xff)];
    }

    final widths = <int, double>{};
    var defaultWidth = 500.0;
    var widthScale = 1.0;
    List<String?>? encoding;
    var builtinTeX = false;

    if (isComposite) {
      final descendants = resolve(dict['DescendantFonts']);
      final desc = descendants is List && descendants.isNotEmpty ? resolve(descendants.first) : null;
      if (desc is Map) {
        final d = desc as PdfDict;
        defaultWidth = ((resolve(d['DW']) as num?) ?? 1000).toDouble();
        final w = resolve(d['W']);
        if (w is List) {
          var i = 0;
          while (i < w.length) {
            final first = resolve(w[i]);
            if (first is! num || i + 1 >= w.length) break;
            final second = resolve(w[i + 1]);
            if (second is List) {
              for (var k = 0; k < second.length; k++) {
                final v = resolve(second[k]);
                if (v is num) widths[first.toInt() + k] = v.toDouble();
              }
              i += 2;
            } else if (second is num && i + 2 < w.length) {
              final v = resolve(w[i + 2]);
              if (v is num) {
                for (var c = first.toInt(); c <= second.toInt() && c - first.toInt() < 65536; c++) {
                  widths[c] = v.toDouble();
                }
              }
              i += 3;
            } else {
              break;
            }
          }
        }
      }
    } else {
      final firstChar = ((resolve(dict['FirstChar']) as num?) ?? 0).toInt();
      final w = resolve(dict['Widths']);
      if (w is List) {
        for (var k = 0; k < w.length; k++) {
          final v = resolve(w[k]);
          if (v is num) widths[firstChar + k] = v.toDouble();
        }
        if (widths.isNotEmpty) {
          final nonZero = widths.values.where((v) => v > 0).toList();
          if (nonZero.isNotEmpty) defaultWidth = nonZero.reduce((a, b) => a + b) / nonZero.length;
        }
      }
      if (subtype == 'Type3') {
        final m = resolve(dict['FontMatrix']);
        if (m is List && m.isNotEmpty && resolve(m.first) is num) {
          widthScale = (resolve(m.first) as num).toDouble() * 1000;
        }
      }
      // Encoding: base table + /Differences.
      final enc = resolve(dict['Encoding']);
      String? baseName;
      List<Object?>? differences;
      if (enc is PdfName) {
        baseName = enc.value;
      } else if (enc is Map) {
        baseName = (resolve(enc['BaseEncoding']) as PdfName?)?.value;
        final diff = resolve(enc['Differences']);
        if (diff is List) differences = diff;
      }
      encoding = switch (baseName) {
        'WinAnsiEncoding' => _winAnsiEncoding(),
        'MacRomanEncoding' => _macRomanEncoding(),
        _ => _standardEncoding(),
      };
      if (differences != null) {
        var code = 0;
        for (final item in differences) {
          final v = resolve(item);
          if (v is num) {
            code = v.toInt();
          } else if (v is PdfName) {
            if (code >= 0 && code < 256) encoding[code] = glyphNameToUnicode(v.value);
            code++;
          }
        }
      }
      final baseFont = (resolve(dict['BaseFont']) as PdfName?)?.value ?? '';
      builtinTeX = enc == null && RegExp(r'(CM[A-Z]+\d|LM[A-Z]|SF[A-Z]{2}\d)').hasMatch(baseFont);
    }

    return PdfFont._(
      isComposite: isComposite,
      toUnicode: toUnicode,
      codespace: codespace,
      encoding: encoding,
      widths: widths,
      defaultWidth: defaultWidth,
      widthScale: widthScale,
      isBuiltinTeX: builtinTeX,
    );
  }

  List<PdfGlyph> decode(Uint8List bytes) {
    final glyphs = <PdfGlyph>[];
    var i = 0;
    while (i < bytes.length) {
      var len = 1;
      var code = bytes[i];
      // Determine code length from the codespace ranges.
      for (final range in codespace) {
        if (i + range.length > bytes.length) continue;
        var c = 0;
        for (var k = 0; k < range.length; k++) {
          c = (c << 8) | bytes[i + k];
        }
        if (c >= range.low && c <= range.high) {
          len = range.length;
          code = c;
          break;
        }
      }
      if (len == 1) code = bytes[i];
      i += len;
      final width = (widths[code] ?? defaultWidth) * widthScale;
      String text;
      if (toUnicode != null && toUnicode!.containsKey(code)) {
        text = toUnicode![code]!;
      } else if (isComposite) {
        text = ''; // unknown CID without ToUnicode
      } else if (isBuiltinTeX && code < 0x20) {
        text = _texOt1Low[code] ?? '';
      } else {
        text =
            (encoding != null && code < 256 ? encoding![code] : null) ??
            (code >= 0x20 && code < 0x7f ? String.fromCharCode(code) : '');
      }
      glyphs.add(PdfGlyph(text, width, len == 1 && code == 32));
    }
    return glyphs;
  }
}

class PdfCodespaceRange {
  const PdfCodespaceRange(this.length, this.low, this.high);
  final int length;
  final int low;
  final int high;
}

class _CMap {
  final Map<int, String> map = {};
  final List<PdfCodespaceRange> codespace = [];
}

int _hexToInt(Uint8List b) {
  var v = 0;
  for (final x in b) {
    v = (v << 8) | x;
  }
  return v;
}

String _utf16beToString(Uint8List b) {
  if (b.length == 1) return String.fromCharCode(b[0]);
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add((b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

_CMap _parseCMap(Uint8List data) {
  final cmap = _CMap();
  final lexer = PdfLexer(data);
  final operands = <Object?>[];
  String? section;
  while (!lexer.atEnd) {
    final start = lexer.pos;
    Object? token;
    try {
      token = lexer.next();
    } catch (_) {
      break;
    }
    if (lexer.pos == start) lexer.pos++;
    if (token is PdfOperator) {
      switch (token.name) {
        case 'begincodespacerange':
        case 'beginbfchar':
        case 'beginbfrange':
          section = token.name;
          operands.clear();
        case 'endcodespacerange':
          for (var i = 0; i + 1 < operands.length; i += 2) {
            final lo = operands[i], hi = operands[i + 1];
            if (lo is PdfString && hi is PdfString && lo.bytes.isNotEmpty) {
              cmap.codespace.add(PdfCodespaceRange(lo.bytes.length, _hexToInt(lo.bytes), _hexToInt(hi.bytes)));
            }
          }
          section = null;
          operands.clear();
        case 'endbfchar':
          for (var i = 0; i + 1 < operands.length; i += 2) {
            final src = operands[i], dst = operands[i + 1];
            if (src is PdfString && dst is PdfString) {
              cmap.map[_hexToInt(src.bytes)] = _utf16beToString(dst.bytes);
            } else if (src is PdfString && dst is PdfName) {
              final t = glyphNameToUnicode(dst.value);
              if (t != null) cmap.map[_hexToInt(src.bytes)] = t;
            }
          }
          section = null;
          operands.clear();
        case 'endbfrange':
          for (var i = 0; i + 2 < operands.length; i += 3) {
            final lo = operands[i], hi = operands[i + 1], dst = operands[i + 2];
            if (lo is! PdfString || hi is! PdfString) continue;
            final low = _hexToInt(lo.bytes), high = _hexToInt(hi.bytes);
            if (high < low || high - low > 65535) continue;
            if (dst is PdfString) {
              final base = Uint8List.fromList(dst.bytes);
              for (var c = low; c <= high; c++) {
                final offset = c - low;
                final bytes = Uint8List.fromList(base);
                // Increment the last byte(s) by offset.
                var carry = offset;
                for (var k = bytes.length - 1; k >= 0 && carry > 0; k--) {
                  final sum = bytes[k] + carry;
                  bytes[k] = sum & 0xff;
                  carry = sum >> 8;
                }
                cmap.map[c] = _utf16beToString(bytes);
              }
            } else if (dst is List) {
              for (var k = 0; k < dst.length && low + k <= high; k++) {
                final d = dst[k];
                if (d is PdfString) cmap.map[low + k] = _utf16beToString(d.bytes);
              }
            }
          }
          section = null;
          operands.clear();
        default:
          if (section == null) operands.clear();
      }
    } else if (section != null) {
      operands.add(token);
    }
  }
  cmap.codespace.sort((a, b) => a.length.compareTo(b.length));
  return cmap;
}

// ---------------------------------------------------------------------------
// Encodings and glyph names
// ---------------------------------------------------------------------------

List<String?> _asciiBase() => List<String?>.generate(256, (i) => i >= 0x20 && i < 0x7f ? String.fromCharCode(i) : null);

List<String?> _standardEncoding() {
  final t = _asciiBase();
  t[0x27] = '’';
  t[0x60] = '‘';
  const upper = {
    0xA1: '¡',
    0xA2: '¢',
    0xA3: '£',
    0xA5: '¥',
    0xA7: '§',
    0xA9: "'",
    0xAA: '“',
    0xAB: '«',
    0xAE: 'fi',
    0xAF: 'fl',
    0xB1: '–',
    0xB2: '†',
    0xB3: '‡',
    0xB4: '·',
    0xB6: '¶',
    0xB7: '•',
    0xB8: '‚',
    0xB9: '„',
    0xBA: '”',
    0xBB: '»',
    0xBC: '…',
    0xBD: '‰',
    0xBF: '¿',
    0xD0: '—',
    0xE1: 'Æ',
    0xE8: 'Ł',
    0xE9: 'Ø',
    0xEA: 'Œ',
    0xF1: 'æ',
    0xF5: 'ı',
    0xF8: 'ł',
    0xF9: 'ø',
    0xFA: 'œ',
    0xFB: 'ß',
  };
  upper.forEach((k, v) => t[k] = v);
  return t;
}

List<String?> _winAnsiEncoding() {
  final t = _asciiBase();
  const cp1252 = '€\u0000‚ƒ„…†‡ˆ‰Š‹Œ\u0000Ž\u0000\u0000‘’“”•–—˜™š›œ\u0000žŸ';
  for (var i = 0; i < 32; i++) {
    final ch = cp1252[i];
    t[0x80 + i] = ch == '\u0000' ? null : ch;
  }
  for (var i = 0xA0; i <= 0xFF; i++) {
    t[i] = String.fromCharCode(i);
  }
  t[0xA0] = ' ';
  t[0xAD] = '';
  return t;
}

List<String?> _macRomanEncoding() {
  final t = _asciiBase();
  const mac =
      'ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø'
      '¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ';
  final runes = mac.runes.toList();
  for (var i = 0; i < 128 && i < runes.length; i++) {
    t[0x80 + i] = String.fromCharCode(runes[i]);
  }
  return t;
}

const Map<int, String> _texOt1Low = {
  0x0B: 'ff',
  0x0C: 'fi',
  0x0D: 'fl',
  0x0E: 'ffi',
  0x0F: 'ffl',
  0x10: 'ı',
  0x11: 'ȷ',
  0x19: 'ß',
  0x1A: 'æ',
  0x1B: 'œ',
  0x1C: 'ø',
  0x1D: 'Æ',
  0x1E: 'Œ',
  0x1F: 'Ø',
};

const Map<String, String> _glyphNames = {
  'space': ' ',
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'quoteright': '’',
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'hyphen': '-',
  'minus': '−',
  'period': '.',
  'slash': '/',
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': r'\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'quoteleft': '‘',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',
  'bullet': '•',
  'endash': '–',
  'emdash': '—',
  'ellipsis': '…',
  'quotedblleft': '“',
  'quotedblright': '”',
  'quotedblbase': '„',
  'quotesinglbase': '‚',
  'guillemotleft': '«',
  'guillemotright': '»',
  'guilsinglleft': '‹',
  'guilsinglright': '›',
  'fi': 'fi',
  'fl': 'fl',
  'ff': 'ff',
  'ffi': 'ffi',
  'ffl': 'ffl',
  'germandbls': 'ß',
  'dagger': '†',
  'daggerdbl': '‡',
  'section': '§',
  'paragraph': '¶',
  'degree': '°',
  'copyright': '©',
  'registered': '®',
  'trademark': '™',
  'multiply': '×',
  'divide': '÷',
  'plusminus': '±',
  'mu': 'µ',
  'periodcentered': '·',
  'cent': '¢',
  'sterling': '£',
  'yen': '¥',
  'Euro': '€',
  'euro': '€',
  'dotlessi': 'ı',
  'ae': 'æ',
  'AE': 'Æ',
  'oe': 'œ',
  'OE': 'Œ',
  'oslash': 'ø',
  'Oslash': 'Ø',
  'lslash': 'ł',
  'Lslash': 'Ł',
  'exclamdown': '¡',
  'questiondown': '¿',
  'perthousand': '‰',
  'nbspace': ' ',
  'uni00A0': ' ',
  'arrowright': '→',
  'arrowleft': '←',
  'lessequal': '≤',
  'greaterequal': '≥',
  'notequal': '≠',
  'infinity': '∞',
  'approxequal': '≈',
  'summation': '∑',
  'product': '∏',
  'integral': '∫',
  'radical': '√',
  'partialdiff': '∂',
  'Delta': 'Δ',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'epsilon': 'ε',
  'lambda': 'λ',
  'pi': 'π',
  'sigma': 'σ',
  'theta': 'θ',
  'omega': 'ω',
  'Omega': 'Ω',
  'Sigma': 'Σ',
  'Pi': 'Π',
  'logicalnot': '¬',
  'ordfeminine': 'ª',
  'ordmasculine': 'º',
  'onehalf': '½',
  'onequarter': '¼',
  'threequarters': '¾',
  'florin': 'ƒ',
};

const Map<String, String> _accents = {
  'dieresis': '̈',
  'acute': '́',
  'grave': '̀',
  'circumflex': '̂',
  'tilde': '̃',
  'ring': '̊',
  'cedilla': '̧',
  'caron': '̌',
  'macron': '̄',
  'breve': '̆',
  'ogonek': '̨',
  'dotaccent': '̇',
  'hungarumlaut': '̋',
};

const Map<String, String> _precomposed = {
  'ä': 'ä',
  'ö': 'ö',
  'ü': 'ü',
  'Ä': 'Ä',
  'Ö': 'Ö',
  'Ü': 'Ü',
  'ë': 'ë',
  'ï': 'ï',
  'ÿ': 'ÿ',
  'Ë': 'Ë',
  'Ï': 'Ï',
  'á': 'á',
  'é': 'é',
  'í': 'í',
  'ó': 'ó',
  'ú': 'ú',
  'ý': 'ý',
  'Á': 'Á',
  'É': 'É',
  'Í': 'Í',
  'Ó': 'Ó',
  'Ú': 'Ú',
  'à': 'à',
  'è': 'è',
  'ì': 'ì',
  'ò': 'ò',
  'ù': 'ù',
  'À': 'À',
  'È': 'È',
  'â': 'â',
  'ê': 'ê',
  'î': 'î',
  'ô': 'ô',
  'û': 'û',
  'Â': 'Â',
  'Ê': 'Ê',
  'Ô': 'Ô',
  'ã': 'ã',
  'ñ': 'ñ',
  'õ': 'õ',
  'Ñ': 'Ñ',
  'å': 'å',
  'Å': 'Å',
  'ç': 'ç',
  'Ç': 'Ç',
  'š': 'š',
  'Š': 'Š',
  'ž': 'ž',
  'Ž': 'Ž',
  'č': 'č',
  'Č': 'Č',
  'ř': 'ř',
  'ě': 'ě',
};

/// Maps a PostScript glyph name to Unicode (subset of the Adobe Glyph List).
String? glyphNameToUnicode(String name) {
  var n = name;
  final dot = n.indexOf('.');
  if (dot > 0) n = n.substring(0, dot);
  if (n.contains('_')) {
    final parts = n.split('_').map(glyphNameToUnicode).toList();
    return parts.contains(null) ? null : parts.join();
  }
  final direct = _glyphNames[n];
  if (direct != null) return direct;
  if (n.length == 1) return n;
  final uni = RegExp(r'^uni([0-9A-Fa-f]{4,})$').firstMatch(n);
  if (uni != null) {
    final hex = uni[1]!;
    final buffer = StringBuffer();
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      buffer.writeCharCode(int.parse(hex.substring(i, i + 4), radix: 16));
    }
    return buffer.toString();
  }
  final u = RegExp(r'^u([0-9A-Fa-f]{4,6})$').firstMatch(n);
  if (u != null) return String.fromCharCode(int.parse(u[1]!, radix: 16));
  for (final entry in _accents.entries) {
    if (n.length == entry.key.length + 1 && n.endsWith(entry.key)) {
      final combined = n[0] + entry.value;
      return _precomposed[combined] ?? combined;
    }
  }
  return null;
}

/// Exposed for tests.
String decodeLatin1(List<int> bytes) => latin1.decode(bytes);
