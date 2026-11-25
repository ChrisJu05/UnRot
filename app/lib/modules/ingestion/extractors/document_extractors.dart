import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../text_extractor.dart';
import 'html_text.dart';
import 'plain_text_extractor.dart';

class HtmlExtractor implements TextExtractor {
  @override
  String get formatId => 'html';

  @override
  Set<String> get extensions => const {'html', 'htm', 'xhtml'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    final html = decodeText(bytes);
    final title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim();
    final text = htmlToText(html);
    if (text.isEmpty) throw ExtractionException('No readable text found in this HTML file.');
    return ExtractedDocument(
      title: (title == null || title.isEmpty) ? titleFromFileName(fileName) : decodeEntities(title),
      text: text,
    );
  }
}

/// EPUB 2/3 e-books: reads the OPF spine and converts each chapter.
class EpubExtractor implements TextExtractor {
  @override
  String get formatId => 'epub';

  @override
  Set<String> get extensions => const {'epub'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ExtractionException('This EPUB file could not be opened (not a valid zip archive).');
    }
    String readString(String name) =>
        utf8.decode(archive.findFile(name)?.content ?? Uint8List(0), allowMalformed: true);

    if (archive.findFile('META-INF/encryption.xml') != null &&
        readString('META-INF/encryption.xml').contains('EncryptedData')) {
      throw ExtractionException('This EPUB is DRM-protected and cannot be imported.');
    }

    final container = XmlDocument.parse(readString('META-INF/container.xml'));
    final opfPath = container.findAllElements('rootfile', namespaceUri: '*').firstOrNull?.getAttribute('full-path');
    if (opfPath == null) throw ExtractionException('Invalid EPUB: missing package document.');
    final opf = XmlDocument.parse(readString(opfPath));
    final baseDir = p.posix.dirname(opfPath);

    final title = opf.findAllElements('title', namespaceUri: '*').firstOrNull?.innerText.trim();
    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final type = item.getAttribute('media-type') ?? '';
      if (id != null && href != null && type.contains('html')) {
        manifest[id] = baseDir == '.' ? href : p.posix.normalize(p.posix.join(baseDir, Uri.decodeFull(href)));
      }
    }
    final buffer = StringBuffer();
    for (final ref in opf.findAllElements('itemref', namespaceUri: '*')) {
      final path = manifest[ref.getAttribute('idref')];
      if (path == null) continue;
      final chapter = htmlToText(readString(path));
      if (chapter.trim().isEmpty) continue;
      buffer
        ..writeln(chapter)
        ..writeln();
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw ExtractionException('No readable text found in this EPUB.');
    return ExtractedDocument(title: (title == null || title.isEmpty) ? titleFromFileName(fileName) : title, text: text);
  }
}

/// Word documents (.docx). Paragraph styles named "Heading N"/"Title" become headings.
class DocxExtractor implements TextExtractor {
  @override
  String get formatId => 'docx';

  @override
  Set<String> get extensions => const {'docx'};

  @override
  Future<ExtractedDocument> extract(Uint8List bytes, {required String fileName}) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ExtractionException('This DOCX file could not be opened (not a valid zip archive).');
    }
    final doc = archive.findFile('word/document.xml');
    if (doc == null) throw ExtractionException('Invalid DOCX: missing word/document.xml.');
    final xml = XmlDocument.parse(utf8.decode(doc.content, allowMalformed: true));

    // Map style ids to names so localised heading styles ("Überschrift 1") are detected.
    final styleNames = <String, String>{};
    final stylesFile = archive.findFile('word/styles.xml');
    if (stylesFile != null) {
      final styles = XmlDocument.parse(utf8.decode(stylesFile.content, allowMalformed: true));
      for (final style in styles.findAllElements('style', namespaceUri: '*')) {
        final id = style.getAttribute('styleId', namespaceUri: '*');
        final name = style.findElements('name', namespaceUri: '*').firstOrNull?.getAttribute('val', namespaceUri: '*');
        if (id != null && name != null) styleNames[id] = name;
      }
    }

    final buffer = StringBuffer();
    String? firstTitle;
    for (final para in xml.findAllElements('p', namespaceUri: '*')) {
      final text = StringBuffer();
      for (final node in para.descendants.whereType<XmlElement>()) {
        switch (node.localName) {
          case 't':
            text.write(node.innerText);
          case 'tab':
            text.write(' ');
          case 'br':
            text.write('\n');
        }
      }
      final line = text.toString().trim();
      if (line.isEmpty) continue;
      final styleId = para
          .findAllElements('pStyle', namespaceUri: '*')
          .firstOrNull
          ?.getAttribute('val', namespaceUri: '*');
      final styleName = (styleNames[styleId] ?? styleId ?? '').toLowerCase();
      final level = _headingLevel(styleName);
      if (level != null) {
        firstTitle ??= line;
        buffer.write('\n${'#' * level} $line\n\n');
      } else if (para.findAllElements('numPr', namespaceUri: '*').isNotEmpty) {
        buffer.write('- $line\n');
      } else {
        buffer.write('$line\n\n');
      }
    }
    var title = titleFromFileName(fileName);
    final core = archive.findFile('docProps/core.xml');
    if (core != null) {
      final coreTitle = XmlDocument.parse(utf8.decode(core.content, allowMalformed: true))
          .findAllElements('title', namespaceUri: '*')
          .firstOrNull
          ?.innerText
          .trim();
      if (coreTitle != null && coreTitle.isNotEmpty) title = coreTitle;
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw ExtractionException('No readable text found in this document.');
    return ExtractedDocument(title: title, text: text);
  }

  static int? _headingLevel(String style) {
    if (style == 'title') return 1;
    final m = RegExp(r'(heading|überschrift|titre|titolo|título|kop)\s*(\d)').firstMatch(style);
    if (m != null) return (int.parse(m[2]!)).clamp(1, 6);
    return null;
  }
}
