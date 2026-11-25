import 'dart:convert';
import 'dart:typed_data';

import '../text_extractor.dart';

/// Decodes bytes as UTF-8 (falling back to Latin-1 / Windows-1252 for legacy files).
String decodeText(Uint8List bytes) {
  var data = bytes;
  // UTF-16 with BOM
  if (data.length >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))) {
    final little = data[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < data.length; i += 2) {
      units.add(little ? data[i] | (data[i + 1] << 8) : (data[i] << 8) | data[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }
  try {
    return utf8.decode(data);
  } on FormatException {
    return latin1.decode(data);
  }
}

class PlainTextExtractor implements TextExtractor {
  @override
  String get formatId => 'text';

  @override
  Set<String> get extensions => const {'txt', 'text'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    final text = decodeText(bytes);
    if (text.trim().isEmpty) throw ExtractionException('The file is empty.');
    return ExtractedDocument(title: titleFromFileName(fileName), text: text);
  }
}

class MarkdownExtractor implements TextExtractor {
  @override
  String get formatId => 'markdown';

  @override
  Set<String> get extensions => const {'md', 'markdown'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    var text = decodeText(bytes);
    if (text.trim().isEmpty) throw ExtractionException('The file is empty.');
    // Drop YAML front matter, images and link targets; keep headings and text.
    text = text.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '');
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!);
    final firstHeading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(text)?.group(1)?.trim();
    return ExtractedDocument(title: firstHeading ?? titleFromFileName(fileName), text: text);
  }
}
