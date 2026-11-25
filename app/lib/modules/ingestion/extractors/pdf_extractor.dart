import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../text_extractor.dart';
import 'pdf/pdf_document.dart';
import 'pdf/pdf_objects.dart';

/// PDF import.
///
/// Uses the built-in pure Dart parser (works on every platform, recognises
/// headings by font size). On desktop, the system `pdftotext` (poppler) is
/// used as a fallback when the built-in parser fails or finds little text
/// (e.g. encrypted files or unusual fonts).
class PdfTextExtractor implements TextExtractor {
  PdfTextExtractor({this.allowSystemFallback = true});

  final bool allowSystemFallback;

  @override
  String get formatId => 'pdf';

  @override
  Set<String> get extensions => const {'pdf'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    final title = _pdfTitle(bytes) ?? titleFromFileName(fileName);
    String? builtIn;
    Object? builtInError;
    var pageCount = 0;
    var unmapped = false;
    try {
      final parser = PdfDocumentParser(bytes);
      final pages = parser.extractPages();
      pageCount = pages.length;
      unmapped = parser.unmappedFonts;
      builtIn = assemblePdfText(pages);
    } on PdfEncryptedException {
      builtInError = 'This PDF is encrypted.';
    } catch (e) {
      builtInError = e;
    }

    final poorQuality = builtIn == null || builtIn.trim().length < 40 * (pageCount == 0 ? 1 : pageCount) || unmapped;
    if (poorQuality && allowSystemFallback) {
      final system = await _runPdftotext(bytes);
      if (system != null && system.trim().length > (builtIn?.trim().length ?? 0)) {
        return ExtractedDocument(
          title: title,
          text: system,
          warnings: const ['Imported with the system pdftotext tool.'],
        );
      }
    }
    if (builtIn == null || builtIn.trim().isEmpty) {
      if (builtInError == 'This PDF is encrypted.') {
        throw ExtractionException(
          'This PDF is encrypted. Remove the protection (e.g. "Print to PDF") or install poppler (pdftotext) and try again.',
        );
      }
      throw ExtractionException('No text found in this PDF. Scanned PDFs need OCR, which is not supported yet.');
    }
    return ExtractedDocument(
      title: title,
      text: builtIn,
      warnings: [if (unmapped) 'Some text uses fonts without a Unicode mapping and may be missing.'],
    );
  }

  static Future<String?> _runPdftotext(Uint8List bytes) async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) return null;
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('unrot_pdf');
      final input = File(p.join(tmp.path, 'in.pdf'));
      await input.writeAsBytes(bytes);
      final result = await Process.run('pdftotext', [
        '-enc',
        'UTF-8',
        input.path,
        '-',
      ]).timeout(const Duration(minutes: 2));
      if (result.exitCode != 0) return null;
      final out = result.stdout is String ? result.stdout as String : '';
      return out.replaceAll('\f', '\n\n');
    } catch (_) {
      return null; // not installed
    } finally {
      try {
        await tmp?.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String? _pdfTitle(Uint8List bytes) {
    // Cheap scan for an /Info /Title entry (uncompressed metadata only).
    try {
      final text = String.fromCharCodes(bytes.length > 4000000 ? bytes.sublist(bytes.length - 4000000) : bytes);
      final match = RegExp(r'/Title\s*(\(|<)').allMatches(text).lastOrNull;
      if (match == null) return null;
      final value = PdfLexer(
        bytes.length > 4000000 ? bytes.sublist(bytes.length - 4000000) : bytes,
        match.end - 1,
      ).next();
      if (value is PdfString) {
        final t = value.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.length >= 3 && t.length < 200 && !t.toLowerCase().startsWith('microsoft word') && !t.endsWith('.dvi')) {
          return t;
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Turns extracted lines into text with Markdown headings and paragraphs.
/// Removes running headers/footers and page numbers.
String assemblePdfText(List<PdfPageText> pages) {
  final all = pages.expand((pg) => pg.lines).toList();
  if (all.isEmpty) return '';

  // Body font size = size covering the most characters.
  final sizeWeights = <int, int>{};
  for (final l in all) {
    final key = (l.fontSize * 2).round();
    sizeWeights[key] = (sizeWeights[key] ?? 0) + l.text.length;
  }
  final bodySize = (sizeWeights.entries.reduce((a, b) => a.value >= b.value ? a : b).key) / 2;

  // Typical gap between body lines.
  final gaps =
      all
          .where((l) => (l.fontSize - bodySize).abs() < bodySize * 0.15 && l.gapBefore > 0.5 && l.gapBefore < 4)
          .map((l) => l.gapBefore)
          .toList()
        ..sort();
  final medianGap = gaps.isEmpty ? 1.2 : gaps[gaps.length ~/ 2];
  final paragraphGap = (medianGap * 1.3).clamp(medianGap + 0.25, 10.0);

  // Running headers/footers: repeated first/last lines.
  String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ');
  final freq = <String, int>{};
  for (final page in pages) {
    final n = page.lines.length;
    final edgeIdx = {0, 1, n - 2, n - 1}.where((i) => i >= 0 && i < n);
    for (final i in edgeIdx) {
      final key = norm(page.lines[i].text.toString());
      if (key.length < 80) freq[key] = (freq[key] ?? 0) + 1;
    }
  }
  final repeatThreshold = pages.length >= 4 ? (pages.length * 0.4).ceil().clamp(3, 1 << 30) : 1 << 30;

  final out = StringBuffer();
  for (final page in pages) {
    final n = page.lines.length;
    var lastWasHeading = false;
    double? lastHeadingSize;
    for (var i = 0; i < n; i++) {
      final line = page.lines[i];
      final text = line.text.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      if (text.isEmpty) continue;
      final isEdge = i < 2 || i >= n - 2;
      if (isEdge && (freq[norm(text)] ?? 0) >= repeatThreshold) continue;
      if ((i == 0 || i == n - 1) &&
          RegExp(r'^(\d{1,4}|[ivxlc]{1,6}|-\s*\d+\s*-|page \d+.*|seite \d+.*)$', caseSensitive: false).hasMatch(text)) {
        continue;
      }
      final words = text.split(' ').length;
      final isHeading =
          line.fontSize >= bodySize * 1.18 &&
          text.length <= 120 &&
          words <= 18 &&
          RegExp(r'[A-Za-zÀ-ž]').hasMatch(text);
      if (isHeading) {
        final level = line.fontSize >= bodySize * 1.7 ? 1 : (line.fontSize >= bodySize * 1.35 ? 2 : 3);
        if (lastWasHeading && lastHeadingSize != null && (lastHeadingSize - line.fontSize).abs() < 0.5) {
          out.write(' $text'); // multi-line heading
        } else {
          out.write('\n\n${'#' * level} $text');
        }
        lastWasHeading = true;
        lastHeadingSize = line.fontSize;
        continue;
      }
      if (lastWasHeading) {
        out.write('\n\n');
      } else if (out.isNotEmpty) {
        out.write(line.gapBefore > paragraphGap ? '\n\n' : '\n');
      }
      out.write(text);
      lastWasHeading = false;
    }
    out.write('\n\n');
  }
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
