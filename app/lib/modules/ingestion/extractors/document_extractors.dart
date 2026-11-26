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
    final images = ImageCollector();
    final buffer = StringBuffer();
    for (final ref in opf.findAllElements('itemref', namespaceUri: '*')) {
      final path = manifest[ref.getAttribute('idref')];
      if (path == null) continue;
      final html = _replaceImages(readString(path), (src, alt) {
        final imagePath = p.posix.normalize(p.posix.join(p.posix.dirname(path), Uri.decodeFull(src)));
        return images.add(imagePath, archive.findFile(imagePath)?.content, alt);
      });
      final chapter = htmlToText(html);
      if (chapter.trim().isEmpty) continue;
      buffer
        ..writeln(chapter)
        ..writeln();
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw ExtractionException('No readable text found in this EPUB.');
    return ExtractedDocument(
      title: (title == null || title.isEmpty) ? titleFromFileName(fileName) : title,
      text: text,
      images: images.images,
    );
  }

  /// Replaces `<img>` tags and SVG-wrapped `<image>` elements with figure markers.
  static String _replaceImages(String html, String Function(String src, String alt) marker) {
    String attr(String tag, String name) =>
        RegExp(
          '$name\\s*=\\s*("([^"]*)"|\'([^\']*)\')',
          caseSensitive: false,
        ).firstMatch(tag)?.let((m) => m[2] ?? m[3]) ??
        '';
    var out = html.replaceAllMapped(RegExp(r'<svg\b[\s\S]*?</svg\s*>', caseSensitive: false), (m) {
      final image = RegExp(r'<image\b[^>]*>', caseSensitive: false).firstMatch(m[0]!);
      if (image == null) return m[0]!;
      final src = attr(image[0]!, '(?:xlink:)?href');
      return src.isEmpty ? m[0]! : '<p>${marker(src, '')}</p>';
    });
    out = out.replaceAllMapped(RegExp(r'<img\b[^>]*>', caseSensitive: false), (m) {
      final src = attr(m[0]!, 'src');
      return src.isEmpty ? '' : '<p>${marker(src, attr(m[0]!, 'alt'))}</p>';
    });
    return out;
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Collects document images and hands out figure markers.
class ImageCollector {
  final List<ExtractedImage> images = [];
  final Map<String, String> _idsByKey = {};

  /// Registers an image (by path or any stable key) and returns its marker text,
  /// or an empty string if the image is unusable (too small, too big, unsupported).
  String add(String key, Uint8List? bytes, String caption, {String? extension}) {
    final existing = _idsByKey[key];
    if (existing != null) return figureMarkerText(existing, caption);
    if (bytes == null || bytes.length < minImageBytes || bytes.length > maxImageBytes) return '';
    if (images.length >= maxImagesPerSource) return '';
    final ext = extension ?? imageExtension(key);
    if (ext == null || ext == 'svg') return '';
    final id = 'img${images.length + 1}';
    images.add(ExtractedImage(id: id, bytes: bytes, extension: ext, caption: caption));
    _idsByKey[key] = id;
    return figureMarkerText(id, caption);
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

    // Relationship ids -> media files (images).
    final rels = <String, String>{};
    final relsFile = archive.findFile('word/_rels/document.xml.rels');
    if (relsFile != null) {
      final relsXml = XmlDocument.parse(utf8.decode(relsFile.content, allowMalformed: true));
      for (final r in relsXml.findAllElements('Relationship', namespaceUri: '*')) {
        final id = r.getAttribute('Id'), target = r.getAttribute('Target');
        if (id != null && target != null) rels[id] = p.posix.normalize(p.posix.join('word', target));
      }
    }
    final images = ImageCollector();

    final buffer = StringBuffer();
    String? firstTitle;
    for (final para in xml.findAllElements('p', namespaceUri: '*')) {
      // Figures anchored in this paragraph.
      for (final blip in para.findAllElements('blip', namespaceUri: '*')) {
        final target = rels[blip.getAttribute('embed', namespaceUri: '*') ?? ''];
        if (target == null) continue;
        final drawing = blip.ancestors.whereType<XmlElement>().where((e) => e.localName == 'drawing').firstOrNull;
        final docPr = drawing?.findAllElements('docPr', namespaceUri: '*').firstOrNull;
        final caption = docPr?.getAttribute('descr') ?? docPr?.getAttribute('title') ?? '';
        buffer.write(images.add(target, archive.findFile(target)?.content, caption));
      }
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
    return ExtractedDocument(title: title, text: text, images: images.images);
  }

  static int? _headingLevel(String style) {
    if (style == 'title') return 1;
    final m = RegExp(r'(heading|überschrift|titre|titolo|título|kop)\s*(\d)').firstMatch(style);
    if (m != null) return (int.parse(m[2]!)).clamp(1, 6);
    return null;
  }
}
