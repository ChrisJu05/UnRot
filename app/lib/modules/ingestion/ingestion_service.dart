import 'dart:isolate';
import 'dart:typed_data';

import '../../core/models/chunk.dart';
import '../../core/models/source.dart';
import '../../core/storage/repositories.dart';
import '../../core/util/ids.dart';
import 'chunker.dart';
import 'extractors/document_extractors.dart';
import 'extractors/pdf_extractor.dart';
import 'extractors/plain_text_extractor.dart';
import 'text_extractor.dart';

/// All built-in extractors. Add new formats here.
ExtractorRegistry defaultExtractorRegistry({bool allowPdfSystemFallback = true}) => ExtractorRegistry([
  PlainTextExtractor(),
  MarkdownExtractor(),
  HtmlExtractor(),
  EpubExtractor(),
  DocxExtractor(),
  PdfTextExtractor(allowSystemFallback: allowPdfSystemFallback),
]);

/// Links figure markers in each chunk's text to the extracted image files.
List<SourceChunk> attachImages(List<SourceChunk> chunks, List<ExtractedImage> images) {
  if (images.isEmpty) return chunks;
  final byId = {for (final img in images) img.id: img};
  return [
    for (final c in chunks)
      c.copyWith(
        images: [
          for (final m in figureMarker.allMatches(c.text))
            if (byId[m[1]] != null)
              ChunkImage(
                id: m[1]!,
                file: '${m[1]}.${byId[m[1]]!.extension}',
                caption: (m[2] ?? '').trim().isNotEmpty ? m[2]!.trim() : byId[m[1]]!.caption,
              ),
        ],
      ),
  ];
}

class ImportResult {
  ImportResult(this.source, this.chunks, this.warnings);
  final StudySource source;
  final List<SourceChunk> chunks;
  final List<String> warnings;
}

class _Extracted {
  _Extracted(this.formatId, this.document, this.chunks);
  final String formatId;
  final ExtractedDocument document;
  final List<SourceChunk> chunks;
}

/// Turns files or pasted text into [StudySource]s with chunks and stores them.
class IngestionService {
  IngestionService(this._library, {this.allowPdfSystemFallback = true});

  final LibraryRepository _library;
  bool allowPdfSystemFallback;

  Set<String> get supportedExtensions => defaultExtractorRegistry().supportedExtensions;

  Future<ImportResult> importFile(Uint8List bytes, String fileName, {SourceStudySettings? study}) async {
    final sourceId = newId('s');
    final allowFallback = allowPdfSystemFallback;
    // Heavy parsing runs off the UI thread.
    final extracted = await Isolate.run(() async {
      final registry = defaultExtractorRegistry(allowPdfSystemFallback: allowFallback);
      final extractor = registry.forFile(fileName);
      if (extractor == null) {
        throw ExtractionException('Unsupported file type. Supported: ${registry.supportedExtensions.join(', ')}');
      }
      final doc = await extractor.extract(bytes, fileName: fileName);
      final chunks = attachImages(const Chunker().chunk(sourceId, doc.text, fallbackTitle: 'Part'), doc.images);
      return _Extracted(extractor.formatId, doc, chunks);
    });
    if (extracted.chunks.isEmpty) throw ExtractionException('No usable text found in "$fileName".');
    final source = StudySource(
      id: sourceId,
      title: extracted.document.title,
      format: extracted.formatId,
      originalFileName: fileName,
      addedAt: DateTime.now(),
      study: study,
    );
    // Store the figures that ended up in sections.
    final byId = {for (final img in extracted.document.images) img.id: img};
    await _library.saveImages(sourceId, {
      for (final c in extracted.chunks)
        for (final img in c.images)
          if (byId[img.id] != null) img.file: byId[img.id]!.bytes,
    });
    await _library.addSource(source, extracted.chunks);
    return ImportResult(source, extracted.chunks, extracted.document.warnings);
  }

  Future<ImportResult> importText(
    String title,
    String text, {
    SourceStudySettings? study,
    String format = 'paste',
  }) async {
    if (text.trim().length < 40) throw ExtractionException('Please paste a bit more text (at least a few sentences).');
    final sourceId = newId('s');
    final chunks = const Chunker().chunk(sourceId, text);
    final source = StudySource(
      id: sourceId,
      title: title.trim().isEmpty ? 'Pasted notes' : title.trim(),
      format: format,
      addedAt: DateTime.now(),
      study: study,
    );
    await _library.addSource(source, chunks);
    return ImportResult(source, chunks, const []);
  }
}
