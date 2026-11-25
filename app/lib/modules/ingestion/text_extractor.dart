import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Result of turning a file into plain text.
///
/// Headings should be emitted as Markdown (`# Title`, `## Section`) so the
/// [Chunker] can build a section structure regardless of the input format.
class ExtractedDocument {
  const ExtractedDocument({required this.title, required this.text, this.warnings = const []});

  final String title;
  final String text;
  final List<String> warnings;
}

class ExtractionException implements Exception {
  ExtractionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Converts a file format into text. Implementations must be pure Dart (no
/// Flutter imports) so extraction can run in a background isolate.
abstract class TextExtractor {
  /// Format id stored on the source (`pdf`, `text`, `markdown`, ...).
  String get formatId;

  /// Lower-case file extensions without dot.
  Set<String> get extensions;

  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName});
}

/// Looks up extractors by file extension. Register new formats here.
class ExtractorRegistry {
  ExtractorRegistry(List<TextExtractor> extractors) {
    for (final e in extractors) {
      for (final ext in e.extensions) {
        _byExtension[ext] = e;
      }
    }
  }

  final Map<String, TextExtractor> _byExtension = {};

  Set<String> get supportedExtensions => _byExtension.keys.toSet();

  TextExtractor? forFile(String fileName) {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    return _byExtension[ext];
  }
}

/// Derives a readable title from a file name.
String titleFromFileName(String fileName) {
  final base = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return base.isEmpty ? 'Untitled' : base;
}
