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
import '../study/subjects.dart';

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
  ImportResult(this.source, this.chunks, this.warnings, {this.document});
  final StudySource source;

  /// The sections that were added by this import.
  final List<SourceChunk> chunks;
  final List<String> warnings;
  final SourceDocument? document;
}

class _Extracted {
  _Extracted(this.formatId, this.document, this.chunks);
  final String formatId;
  final ExtractedDocument document;
  final List<SourceChunk> chunks;
}

/// Prefixes figure ids with the document id so they stay unique in collections.
ExtractedDocument prefixImageIds(ExtractedDocument doc, String prefix) {
  if (doc.images.isEmpty) return doc;
  return ExtractedDocument(
    title: doc.title,
    warnings: doc.warnings,
    text: doc.text.replaceAllMapped(figureMarker, (m) => '[[img:$prefix${m[1]}${m[2] != null ? '|${m[2]}' : ''}]]'),
    images: [
      for (final img in doc.images)
        ExtractedImage(id: '$prefix${img.id}', bytes: img.bytes, extension: img.extension, caption: img.caption),
    ],
  );
}

/// Turns files or pasted text into [StudySource]s (or adds them as documents
/// to an existing source / collection) and stores them.
class IngestionService {
  IngestionService(this._library, {this.allowPdfSystemFallback = true});

  final LibraryRepository _library;
  bool allowPdfSystemFallback;

  Set<String> get supportedExtensions => defaultExtractorRegistry().supportedExtensions;

  /// Creates an empty collection that documents can be added to.
  Future<StudySource> createCollection(String title, {SourceStudySettings? study}) async {
    final source = StudySource(
      id: newId('s'),
      title: title.trim().isEmpty ? 'New collection' : title.trim(),
      format: 'collection',
      addedAt: DateTime.now(),
      study: study,
    );
    await _library.addSource(source, const []);
    return source;
  }

  /// Imports a file as a new source, or as a new document of [intoSourceId].
  Future<ImportResult> importFile(
    Uint8List bytes,
    String fileName, {
    SourceStudySettings? study,
    String? intoSourceId,
  }) async {
    final target = intoSourceId == null ? null : _library.source(intoSourceId);
    final sourceId = target?.id ?? newId('s');
    final documentId = target?.nextDocumentId() ?? 'd1';
    final allowFallback = allowPdfSystemFallback;
    // Heavy parsing runs off the UI thread.
    final extracted = await Isolate.run(() async {
      final registry = defaultExtractorRegistry(allowPdfSystemFallback: allowFallback);
      final extractor = registry.forFile(fileName);
      if (extractor == null) {
        throw ExtractionException('Unsupported file type. Supported: ${registry.supportedExtensions.join(', ')}');
      }
      final doc = prefixImageIds(await extractor.extract(bytes, fileName: fileName), '$documentId-');
      final chunks = attachImages(
        const Chunker().chunk(
          sourceId,
          doc.text,
          fallbackTitle: 'Part',
          documentId: documentId,
          idPrefix: '$sourceId:$documentId-',
        ),
        doc.images,
      );
      return _Extracted(extractor.formatId, doc, chunks);
    });
    if (extracted.chunks.isEmpty) throw ExtractionException('No usable text found in "$fileName".');
    // Store the figures that ended up in sections.
    final byId = {for (final img in extracted.document.images) img.id: img};
    await _library.saveImages(sourceId, {
      for (final c in extracted.chunks)
        for (final img in c.images)
          if (byId[img.id] != null) img.file: byId[img.id]!.bytes,
    });
    final document = SourceDocument(
      id: documentId,
      title: extracted.document.title,
      format: extracted.formatId,
      fileName: fileName,
      addedAt: DateTime.now(),
    );
    final source = await _store(target, sourceId, document, extracted.chunks, study);
    return ImportResult(source, extracted.chunks, extracted.document.warnings, document: document);
  }

  /// Imports pasted text as a new source, or as a new document of [intoSourceId].
  Future<ImportResult> importText(
    String title,
    String text, {
    SourceStudySettings? study,
    String format = 'paste',
    String? intoSourceId,
  }) async {
    if (text.trim().length < 40) throw ExtractionException('Please paste a bit more text (at least a few sentences).');
    final target = intoSourceId == null ? null : _library.source(intoSourceId);
    final sourceId = target?.id ?? newId('s');
    final documentId = target?.nextDocumentId() ?? 'd1';
    final chunks = const Chunker().chunk(sourceId, text, documentId: documentId, idPrefix: '$sourceId:$documentId-');
    if (chunks.isEmpty) throw ExtractionException('No usable text found. Please paste a few sentences of text.');
    final document = SourceDocument(
      id: documentId,
      title: title.trim().isEmpty ? 'Pasted notes' : title.trim(),
      format: format,
      addedAt: DateTime.now(),
    );
    final source = await _store(target, sourceId, document, chunks, study);
    return ImportResult(source, chunks, const [], document: document);
  }

  Future<StudySource> _store(
    StudySource? target,
    String sourceId,
    SourceDocument document,
    List<SourceChunk> chunks,
    SourceStudySettings? study,
  ) async {
    if (target != null) {
      await _library.addDocument(target.id, document, chunks);
      // An empty collection takes the subject of its first document.
      if (target.study.subjectId == 'general' && target.documents.length == 1) {
        target.study.subjectId = SubjectProfiles.detect(chunks.map((c) => c.text).join('\n'));
        await _library.updateSource(target);
      }
      return target;
    }
    final settings = study ?? SourceStudySettings();
    if (study == null) settings.subjectId = SubjectProfiles.detect(chunks.map((c) => c.text).join('\n'));
    final source = StudySource(
      id: sourceId,
      title: document.title,
      format: document.format,
      originalFileName: document.fileName,
      addedAt: DateTime.now(),
      study: settings,
      documents: [document],
    );
    await _library.addSource(source, chunks);
    return source;
  }
}
