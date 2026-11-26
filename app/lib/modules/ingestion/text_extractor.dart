import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Result of turning a file into plain text.
///
/// Headings should be emitted as Markdown (`# Title`, `## Section`) so the
/// [Chunker] can build a section structure regardless of the input format.
class ExtractedDocument {
  const ExtractedDocument({required this.title, required this.text, this.warnings = const [], this.images = const []});

  final String title;

  /// Text with Markdown headings; figures appear as `[[img:<id>|caption]]` markers.
  final String text;
  final List<String> warnings;
  final List<ExtractedImage> images;
}

/// An image (figure) found in a document.
class ExtractedImage {
  const ExtractedImage({required this.id, required this.bytes, required this.extension, this.caption = ''});

  final String id;
  final Uint8List bytes;

  /// `jpg`, `png`, `gif`, `webp` or `svg`.
  final String extension;
  final String caption;
}

/// Limits for extracted figures.
const maxImagesPerSource = 300;
const minImageBytes = 1500;
const maxImageBytes = 8 * 1024 * 1024;

/// Builds a figure marker for the text stream (surrounded by blank lines).
String figureMarkerText(String id, [String caption = '']) {
  final clean = caption.replaceAll(RegExp(r'[\[\]|\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return '\n\n[[img:$id${clean.isEmpty ? '' : '|$clean'}]]\n\n';
}

/// Image file extension for a MIME type or file name, or null if unsupported.
String? imageExtension(String nameOrMime) {
  final v = nameOrMime.toLowerCase();
  if (v.contains('jpeg') || v.endsWith('.jpg') || v.endsWith('.jpeg')) return 'jpg';
  if (v.contains('png')) return 'png';
  if (v.contains('gif')) return 'gif';
  if (v.contains('webp')) return 'webp';
  if (v.contains('svg')) return 'svg';
  return null;
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
