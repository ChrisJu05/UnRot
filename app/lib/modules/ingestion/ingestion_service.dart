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
      final chunks = const Chunker().chunk(sourceId, doc.text, fallbackTitle: 'Part');
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
