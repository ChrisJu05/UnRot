import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:unrot/modules/ingestion/chunker.dart';
import 'package:unrot/modules/ingestion/extractors/document_extractors.dart';
import 'package:unrot/modules/ingestion/extractors/html_text.dart';
import 'package:unrot/modules/ingestion/extractors/pdf/pdf_document.dart';
import 'package:unrot/modules/ingestion/extractors/pdf/pdf_fonts.dart';
import 'package:unrot/modules/ingestion/extractors/pdf_extractor.dart';
import 'package:unrot/modules/ingestion/extractors/plain_text_extractor.dart';
import 'package:unrot/modules/ingestion/ingestion_service.dart';
import 'package:unrot/modules/ingestion/text_extractor.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('Chunker', () {
    test('splits on markdown headings and keeps the heading path', () {
      final text = [
        '# Biology',
        '## Cells',
        List.filled(40, 'Cells are the basic unit of life.').join(' '),
        '## Genetics',
        List.filled(40, 'Genes are made of DNA.').join(' '),
      ].join('\n\n');
      final chunks = const Chunker(minChars: 200).chunk('s', text);
      expect(chunks.map((c) => c.title), ['Cells', 'Genetics']);
      expect(chunks.first.headingPath, ['Biology', 'Cells']);
      expect(chunks.first.id, 's:0');
      expect(chunks[1].index, 1);
    });

    test('detects numbered and chapter headings', () {
      final body = List.filled(30, 'This sentence explains the topic in detail.').join(' ');
      final text = 'Chapter 1 Introduction\n\n$body\n\n1.1 Cell Membranes\n\n$body\n\n1.2 Organelles\n\n$body';
      final chunks = const Chunker(minChars: 100).chunk('s', text);
      expect(chunks.map((c) => c.title), contains('1.1 Cell Membranes'));
      expect(chunks.map((c) => c.title), contains('1.2 Organelles'));
    });

    test('splits long sections near the target size', () {
      final text = List.generate(200, (i) => 'Sentence number $i is about something.').join(' ');
      final chunks = const Chunker(targetChars: 1000, maxChars: 1500).chunk('s', text);
      expect(chunks.length, greaterThan(3));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(1600));
      }
    });

    test('removes line-end hyphenation and reflows wrapped lines', () {
      final normalized = Chunker.normalize('The mito-\nchondria produce\nenergy.');
      expect(normalized, contains('mitochondria'));
      final chunks = const Chunker().chunk(
        's',
        'The mito-\nchondria produce\nenergy for the cell. And more text here.',
      );
      expect(chunks.single.text, startsWith('The mitochondria produce energy'));
    });

    test('splitSentences respects abbreviations', () {
      final s = splitSentences('This is e.g. an example. Second sentence here! Third?');
      expect(s, ['This is e.g. an example.', 'Second sentence here!', 'Third?']);
    });
  });

  group('Text formats', () {
    test('plain text handles BOM and Latin-1', () async {
      final utf = await PlainTextExtractor().extract(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Grüße aus München')]),
        fileName: 'notes.txt',
      );
      expect(utf.text, 'Grüße aus München');
      expect(utf.title, 'notes');
      final legacy = await PlainTextExtractor().extract(Uint8List.fromList(latin1.encode('Größe')), fileName: 'a.txt');
      expect(legacy.text, 'Größe');
    });

    test('markdown title, links and front matter', () async {
      final doc = await MarkdownExtractor().extract(
        Uint8List.fromList(utf8.encode('---\ntags: x\n---\n# Physics\nSee [Newton](http://x.org) ![img](a.png)')),
        fileName: 'phys.md',
      );
      expect(doc.title, 'Physics');
      expect(doc.text, contains('See Newton'));
      expect(doc.text, isNot(contains('http://')));
      expect(doc.text, isNot(contains('tags')));
    });

    test('html to text keeps headings and lists', () {
      final text = htmlToText(
        '<html><head><style>p{}</style></head><body><h2>Title &amp; More</h2><p>Hello<br>World</p><ul><li>One</li><li>Two</li></ul></body></html>',
      );
      expect(text, contains('## Title & More'));
      expect(text, contains('Hello\nWorld'));
      expect(text, contains('- One'));
      expect(text, isNot(contains('p{}')));
    });

    test('epub follows the spine order', () async {
      final bytes = _zip({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        'OEBPS/content.opf':
            '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>My Book</dc:title></metadata>'
            '<manifest><item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
        'OEBPS/ch1.xhtml': '<html><body><h1>One</h1><p>First chapter text.</p></body></html>',
        'OEBPS/ch2.xhtml': '<html><body><h1>Two</h1><p>Second chapter text.</p></body></html>',
      });
      final doc = await EpubExtractor().extract(bytes, fileName: 'book.epub');
      expect(doc.title, 'My Book');
      expect(doc.text.indexOf('# One'), lessThan(doc.text.indexOf('# Two')));
      expect(doc.text, contains('Second chapter text.'));
    });

    test('docx headings from styles and LibreOffice fixture', () async {
      final bytes = File('test/fixtures/zellbiologie_libreoffice.docx').readAsBytesSync();
      final doc = await DocxExtractor().extract(bytes, fileName: 'x.docx');
      expect(doc.text, contains('# Kapitel 1: Die Zelle'));
      expect(doc.text, contains('## 1.1 Die Zellmembran'));
      expect(doc.text, contains('„Straße“'));
      expect(doc.text, contains('- Outer membrane'));
    });

    test('registry selects extractors by extension', () {
      final registry = defaultExtractorRegistry(allowPdfSystemFallback: false);
      expect(registry.forFile('a.PDF'), isA<PdfTextExtractor>());
      expect(registry.forFile('b.epub'), isA<EpubExtractor>());
      expect(registry.forFile('c.xyz'), isNull);
      expect(registry.supportedExtensions, containsAll(['pdf', 'txt', 'md', 'docx', 'epub', 'html']));
    });
  });

  group('PDF', () {
    test('LibreOffice PDF: text, umlauts, headings by font size', () async {
      final bytes = File('test/fixtures/zellbiologie_libreoffice.pdf').readAsBytesSync();
      final doc = await PdfTextExtractor(allowSystemFallback: false).extract(bytes, fileName: 'x.pdf');
      expect(doc.title, 'Zellbiologie Skript');
      expect(doc.text, contains('# Kapitel 1: Die Zelle'));
      expect(doc.text, contains('## 1.2 Mitochondrien'));
      expect(doc.text, contains('Grüße an Müller – „Straße“'));
      expect(doc.text, contains('powerhouse of the cell'));
      expect(doc.warnings, isEmpty);
    });

    test('pdf package output (compressed, standard fonts, multiple pages)', () async {
      final document = pw.Document();
      for (var page = 1; page <= 3; page++) {
        document.addPage(
          pw.Page(
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Lecture $page', style: pw.TextStyle(fontSize: 24)),
                pw.SizedBox(height: 12),
                pw.Text('Photosynthesis converts light energy into chemical energy. Page $page explains it.'),
                pw.Text('Chlorophyll absorbs mostly blue and red light.'),
              ],
            ),
          ),
        );
      }
      final bytes = await document.save();
      final doc = await PdfTextExtractor(allowSystemFallback: false).extract(bytes, fileName: 'lecture.pdf');
      expect(doc.text, contains('# Lecture 1'));
      expect(doc.text, contains('# Lecture 3'));
      expect(doc.text, contains('Photosynthesis converts light energy into chemical energy. Page 2 explains it.'));
      expect(doc.text, contains('Chlorophyll absorbs mostly blue and red light.'));
    });

    test('running headers, footers and page numbers are removed', () {
      PdfTextLine line(String text, double size, [double gap = 1.2]) =>
          PdfTextLine(size, gapBefore: gap)..text.write(text);
      final pages = [
        for (var i = 1; i <= 5; i++)
          PdfPageText([
            line('Biology 101 — Winter term', 9),
            line(i == 1 ? 'Introduction' : 'Body text continues on page $i.', i == 1 ? 18 : 11),
            line('Plain body text number $i with enough words to count.', 11),
            line('Another line of body text.', 11),
            line('$i', 9),
          ]),
      ];
      final text = assemblePdfText(pages);
      expect(text, isNot(contains('Winter term')));
      expect(text, isNot(contains(RegExp(r'^\d+$', multiLine: true))));
      expect(text, contains('# Introduction'));
      expect(text, contains('Plain body text number 3'));
    });

    test('glyph names map to unicode', () {
      expect(glyphNameToUnicode('adieresis'), 'ä');
      expect(glyphNameToUnicode('germandbls'), 'ß');
      expect(glyphNameToUnicode('uni00FC'), 'ü');
      expect(glyphNameToUnicode('f_i'), 'fi');
      expect(glyphNameToUnicode('A.sc'), 'A');
      expect(glyphNameToUnicode('quotedblleft'), '“');
    });

    test('garbage input gives a friendly error', () async {
      expect(
        () =>
            PdfTextExtractor(allowSystemFallback: false)
                .extract(Uint8List.fromList(utf8.encode('not a pdf')), fileName: 'x.pdf'),
        throwsA(isA<ExtractionException>()),
      );
    });
  });
}
