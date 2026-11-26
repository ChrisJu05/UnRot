import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:unrot/core/models/chunk.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/models/source.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/modules/generation/generation_job.dart';
import 'package:unrot/modules/generation/offline_generator.dart';
import 'package:unrot/modules/generation/prompt_builder.dart';
import 'package:unrot/modules/generation/reel_parser.dart';
import 'package:unrot/modules/ingestion/extractors/document_extractors.dart';
import 'package:unrot/modules/ingestion/extractors/pdf_extractor.dart';
import 'package:unrot/modules/ingestion/extractors/png_encoder.dart';
import 'package:unrot/modules/ingestion/ingestion_service.dart';
import 'package:unrot/modules/study/modes/builtin_modes.dart';
import 'package:unrot/modules/visuals/expression.dart';
import 'package:unrot/modules/visuals/visual_spec.dart';
import 'package:unrot/ui/visuals/math_text.dart';

double ev(String e, [Map<String, double> vars = const {}]) => Expression.parse(e).eval(vars);

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _png(int w, int h) {
  final random = Random(42);
  // Random pixels so the image does not compress below the "real figure" size threshold.
  final pixels = Uint8List.fromList(List.generate(w * h * 3, (_) => random.nextInt(256)));
  return encodePng(w, h, 3, pixels);
}

GenerationJob job(
  String text, {
  List<String> types = const ['visual'],
  List<ChunkImage> images = const [],
  SourceStudySettings? study,
  GenerationSettings? settings,
}) => GenerationJob(
  source: StudySource(id: 's', title: 'Physics', format: 'text', addedAt: DateTime(2026), study: study),
  chunk: SourceChunk(id: 's:0', sourceId: 's', index: 0, title: 'Forgetting', text: text, images: images),
  chunkCount: 1,
  reelTypes: types,
  mode: const LinearMode(),
  settings: settings ?? GenerationSettings(),
);

void main() {
  group('Expression', () {
    test('arithmetic, precedence, powers and unary minus', () {
      expect(ev('1 + 2 * 3'), 7);
      expect(ev('(1 + 2) * 3'), 9);
      expect(ev('2 ^ 3 ^ 2'), 512);
      expect(ev('-2 ^ 2'), -4);
      expect(ev('2 ^ -1'), 0.5);
      expect(ev('7 % 3'), 1);
      expect(ev('2 ** 3'), 8);
      expect(ev('3 · 4 − 2'), 10);
    });

    test('implicit multiplication', () {
      expect(ev('2x', {'x': 3}), 6);
      expect(ev('3(x+1)', {'x': 1}), 6);
      expect(ev('x(x+1)', {'x': 2}), 6);
      expect(ev('2 sin(0)'), 0);
      expect(ev('2pi'), closeTo(6.2832, 1e-4));
    });

    test('functions, constants, logic and ternary', () {
      expect(ev('sin(pi/2)'), closeTo(1, 1e-12));
      expect(ev('e^(-t/S)', {'t': 0, 'S': 3}), 1);
      expect(ev('ln(e)'), closeTo(1, 1e-12));
      expect(ev('log(100)'), closeTo(2, 1e-12));
      expect(ev('sqrt(16) + abs(-2) + |-3|'), 9);
      expect(ev('max(1, 5, 3) - min(4, 2)'), 3);
      expect(ev('a < 0 && b > 1', {'a': -1, 'b': 2}), 1);
      expect(ev('!(1 > 2) || 0'), 1);
      expect(ev('x > 0 ? 1 : -1', {'x': -5}), -1);
      expect(ev('if(x >= 2, 10, 20)', {'x': 2}), 10);
      expect(ev('(-8)^(1/3)'), closeTo(-2, 1e-9));
      expect(ev('unknown + 1').isNaN, isTrue);
    });

    test('variables are collected and syntax errors are reported', () {
      expect(Expression.parse('a*x^2 + b*sin(x) + pi').variables, {'a', 'x', 'b'});
      expect(() => Expression.parse('2 +'), throwsA(isA<ExprException>()));
      expect(() => Expression.parse('sin(1'), throwsA(isA<ExprException>()));
      expect(() => Expression.parse(r'2 $ 3'), throwsA(isA<ExprException>()));
      expect(Expression.tryParse('import("dart:io")'), isNull);
    });

    test('formatNumber', () {
      expect(formatNumber(2), '2');
      expect(formatNumber(2.5), '2.5');
      expect(formatNumber(1 / 3, decimals: 2), '0.33');
      expect(formatNumber(-0.0001), '0');
    });
  });

  group('VisualNormalizer', () {
    test('function plot: cleans expressions and adds sliders for free variables', () {
      final data = VisualNormalizer.normalize({
        'title': 'Parabola',
        'visual': {
          'kind': 'graph',
          'x_range': [-3, 3],
          'functions': [
            {'expr': 'y = a*x^2 + c', 'label': 'f'},
            {'expr': 'this is not math ((('},
          ],
          'points': [
            {'x': '0', 'y': 'c', 'label': 'vertex'},
          ],
        },
        'controls': [
          {'kind': 'knob', 'param': 'a', 'min': -2, 'max': 2, 'value': 1},
        ],
        'challenge': {'prompt': 'Open downwards', 'condition': 'a < 0'},
      })!;
      final spec = VisualSpec(data);
      expect(spec.kind, 'function_plot');
      expect(spec.functions.single.expr, 'a*x^2 + c');
      expect(spec.xMin, -3);
      expect(spec.controls.map((c) => c.param), ['a', 'c']);
      expect(spec.controls.first.kind, 'dial');
      expect(spec.challenge!.condition, 'a < 0');
      expect(spec.initialParams(), {'a': 1, 'c': 1});
    });

    test('controls: toggle, buttons, stepper, clamping, invalid names', () {
      final data = VisualNormalizer.normalize({
        'visual': {
          'kind': 'function_plot',
          'functions': ['n*x + k*show'],
        },
        'controls': [
          {'kind': 'switch', 'param': 'show', 'value': 1},
          {
            'kind': 'select',
            'param': 'k',
            'options': [
              {'label': 'small', 'value': 1},
              {'label': 'big', 'value': 10},
            ],
          },
          {'kind': 'stepper', 'param': 'n', 'min': 1, 'max': 5, 'value': 99},
          {'kind': 'slider', 'param': 'sin'},
          {'kind': 'slider', 'param': 'x'},
        ],
      })!;
      final controls = VisualSpec(data).controls;
      expect(controls.map((c) => c.kind), ['toggle', 'buttons', 'stepper']);
      expect(controls[1].options.map((o) => o.$2), [1, 10]);
      expect(controls[2].initial, 5);
      expect(controls[2].step, 1);
    });

    test('chart with expression values and animation', () {
      final data = VisualNormalizer.normalize({
        'visual': {
          'kind': 'bar_chart',
          'labels': ['A', 'B'],
          'series': [
            {
              'name': 'Revenue',
              'values': [3, '2*g', 'oops(('],
            },
          ],
        },
        'controls': [
          {'param': 'g', 'min': 0, 'max': 3, 'value': 1},
        ],
        'animate': {'param': 't', 'seconds': 100},
      })!;
      final spec = VisualSpec(data);
      expect(spec.kind, 'chart');
      expect(spec.series.single.values, ['3', '2*g', '0']);
      expect(spec.labels, ['A', 'B', '3']);
      expect(spec.animation!.seconds, 60);
    });

    test('svg diagrams are sanitised and templated', () {
      const svg =
          "<svg viewBox='0 0 100 100' onload='alert(1)'><script>alert(1)</script>"
          "<image href='https://evil.example/x.png'/><circle cx='{{50 + 10*a}}' cy='50' r='{{r}}'/></svg>";
      final data = VisualNormalizer.normalize({
        'visual': {'kind': 'sketch', 'svg': 'Here you go: $svg'},
        'controls': [
          {'param': 'a', 'min': 0, 'max': 2, 'value': 1},
        ],
      })!;
      final spec = VisualSpec(data);
      expect(spec.svg, isNot(contains('script')));
      expect(spec.svg, isNot(contains('onload')));
      expect(spec.svg, isNot(contains('evil.example')));
      expect(spec.svg, contains("xmlns='http://www.w3.org/2000/svg'"));
      expect(spec.controls.map((c) => c.param), ['a', 'r'], reason: 'r was missing and gets a slider');
      final rendered = VisualNormalizer.renderSvgTemplate(spec.svg, {'a': 2, 'r': 7.5});
      expect(rendered, contains("cx='70'"));
      expect(rendered, contains("r='7.5'"));
    });

    test('equation steps, images and garbage', () {
      final eq = VisualSpec(
        VisualNormalizer.normalize({
          'visual': {
            'kind': 'formula',
            'latex': r'a^2 + b^2 = c^2',
            'steps': [
              r'c = \sqrt{a^2+b^2}',
              {'latex': '', 'note': 'Take the root'},
            ],
          },
        })!,
      );
      expect(eq.kind, 'equation');
      expect(eq.steps.map((s) => s.latex), [r'c = \sqrt{a^2+b^2}', '']);
      expect(
        VisualSpec(
          VisualNormalizer.normalize({
            'visual': {'kind': 'image', 'image_id': '[img:img3]'},
          })!,
        ).imageId,
        'img3',
      );
      expect(
        VisualNormalizer.normalize({
          'visual': {'kind': 'image', 'image_url': 'http://insecure/x.png'},
        }),
        isNull,
      );
      expect(
        VisualNormalizer.normalize({
          'visual': {'kind': 'hologram'},
        }),
        isNull,
      );
      expect(
        VisualNormalizer.normalize({
          'visual': {'kind': 'function_plot', 'functions': []},
        }),
        isNull,
      );
    });
  });

  group('Math text', () {
    test('splits inline and display math but leaves prices alone', () {
      final parts = splitMath(r'Energy $E=mc^2$ costs $5 and $10. $$\int_0^1 x\,dx$$ and \(a+b\)');
      expect(parts.where((p) => p.isMath).map((p) => p.text), ['E=mc^2', r'\int_0^1 x\,dx', 'a+b']);
      expect(parts.where((p) => p.display).length, 1);
      expect(parts.where((p) => !p.isMath).map((p) => p.text).join(), contains(r'costs $5 and $10.'));
      expect(splitMath(r'Is it $6a$ or $a^3$?').where((p) => p.isMath).map((p) => p.text), ['6a', 'a^3']);
      expect(splitMath(r'Tickets cost $5, children $3.').where((p) => p.isMath), isEmpty);
    });

    test('repairs LaTeX broken by JSON escapes', () {
      final reels = const ReelParser().parse(
        r'{"reels":[{"type":"explainer","title":"Fractions","body":"Half is $\frac{1}{2}$, the angle $\theta$ and $\sqrt{2}$."}]}',
        job('x', types: ['explainer']),
        generator: 't',
      );
      expect(reels.single.str('body'), r'Half is $\frac{1}{2}$, the angle $\theta$ and $\sqrt{2}$.');
      expect(repairLatex('\frac{1}{2}'), r'\frac{1}{2}');
    });
  });

  group('Generation with visuals', () {
    test('visual requests are sent without a strict schema and parsed', () {
      final j = job('text', types: ['visual', 'quiz']);
      expect(const PromptBuilder().schema(j), isNull);
      expect(const PromptBuilder().user(j), contains('function_plot'));
      final reels = const ReelParser().parse(
        '{"reels":[{"type":"visual","title":"Decay","caption":"Watch it","visual":{"kind":"function_plot",'
        '"functions":[{"expr":"exp(-x/S)"}]},"controls":[{"kind":"slider","param":"S","min":1,"max":5,"value":2}],'
        '"animate":null,"challenge":null}]}',
        j,
        generator: 't',
      );
      expect(VisualSpec(reels.single.data).functions.single.expr, 'exp(-x/S)');
    });

    test('offline generator plots formulas from the text', () async {
      final reels = await OfflineReelGenerator().generate(
        job(
          'A simple model of it is R(t) = e^(-t/S), where R is the share you still remember, t is the time in days '
          'and S is the stability of the memory. Reviews make the curve flatter over time.',
        ),
      );
      final spec = VisualSpec(reels.single.data);
      expect(spec.kind, 'function_plot');
      expect(spec.functions.single.expr, 'e^(-x/S)');
      expect(spec.controls.single.param, 'S');
      expect(spec.xMin, 0);
    });

    test('offline generator shows figures of the section', () async {
      final reels = await OfflineReelGenerator().generate(
        job(
          'The cell membrane surrounds the cell. [[img:img2|Figure 1: Cell membrane]] It is made of lipids and proteins.',
          images: const [ChunkImage(id: 'img2', file: 'img2.png', caption: 'Figure 1: Cell membrane')],
        ),
      );
      final spec = VisualSpec(reels.single.data);
      expect(spec.kind, 'image');
      expect(spec.imageId, 'img2');
      expect(spec.caption, contains('Cell membrane'));
    });

    test('figures are listed in the prompt and markers are readable', () {
      final j = job(
        'Text before. [[img:img4|Figure 2: Mitochondrion]] Text after.',
        images: const [ChunkImage(id: 'img4', file: 'img4.jpg', caption: 'Figure 2: Mitochondrion')],
      );
      final prompt = const PromptBuilder().user(j);
      expect(prompt, contains('img4: Figure 2: Mitochondrion'));
      expect(prompt, contains('[Figure img4: Figure 2: Mitochondrion]'));
      expect(prompt, isNot(contains('[[img:')));
    });
  });

  group('Reel language', () {
    test('per-source language overrides the app default', () {
      final english = job('Die Zelle', study: SourceStudySettings(reelLanguage: 'English'));
      expect(english.language, 'English');
      expect(const PromptBuilder().system(english), contains('translate everything into English'));
      final defaulted = job('x', settings: GenerationSettings(language: 'Deutsch'));
      expect(defaulted.language, 'Deutsch');
      final source = job(
        'x',
        study: SourceStudySettings(reelLanguage: 'source'),
        settings: GenerationSettings(language: 'English'),
      );
      expect(source.language, 'source');
      expect(const PromptBuilder().system(source), contains('same language as the source'));
    });

    test('settings round-trip', () {
      final s = SourceStudySettings.fromJson(SourceStudySettings(reelLanguage: 'English').toJson());
      expect(s.reelLanguage, 'English');
      expect(SourceStudySettings.fromJson(const {}).reelLanguage, 'default');
      final g = GenerationSettings.fromJson(GenerationSettings(visualLevel: 'lots', allowWebImages: true).toJson());
      expect(g.visualLevel, 'lots');
      expect(g.allowWebImages, isTrue);
      expect(GenerationSettings(visualLevel: 'off').visualWeightFactor, 0);
    });
  });

  group('Figure extraction', () {
    test('PDF: JPEG and raw RGB images become figures with captions', () async {
      final jpeg = File('test/fixtures/figure.jpg').readAsBytesSync();
      final document = pw.Document();
      document.addPage(
        pw.Page(
          build: (_) => pw.Column(
            children: [
              pw.Text('Photosynthesis happens in the chloroplast. It converts light into chemical energy.'),
              pw.Image(pw.MemoryImage(jpeg), width: 160),
              pw.Text('Figure 1: A chloroplast'),
              pw.Image(pw.MemoryImage(_png(160, 120)), width: 120),
              pw.Text('More text about the Calvin cycle and the light reactions in plants.'),
            ],
          ),
        ),
      );
      final doc = await PdfTextExtractor(allowSystemFallback: false).extract(await document.save(), fileName: 'p.pdf');
      expect(doc.images.length, 2);
      expect(doc.images.map((i) => i.extension).toSet(), {'jpg', 'png'});
      expect(doc.images.first.bytes.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
      expect(doc.text, contains('[[img:img1|Figure 1: A chloroplast]]'));
      expect(doc.text, contains('[[img:img2]]'));
      expect(doc.text.indexOf('[[img:img1'), lessThan(doc.text.indexOf('Figure 1: A chloroplast]]') + 100));
    });

    test('EPUB and DOCX images', () async {
      final png = _png(100, 80);
      final epub = _zip({
        'META-INF/container.xml': utf8.encode(
          '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        ),
        'OPS/book.opf': utf8.encode(
          '<package xmlns="http://www.idpf.org/2007/opf"><metadata/><manifest><item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>',
        ),
        'OPS/text/c1.xhtml': utf8.encode(
          '<html><body><h1>Cells</h1><p>Cells are small.</p><img src="../images/cell.png" alt="A cell"/><p>The end.</p></body></html>',
        ),
        'OPS/images/cell.png': png,
      });
      final e = await EpubExtractor().extract(epub, fileName: 'b.epub');
      expect(e.images.single.extension, 'png');
      expect(e.text, contains('[[img:img1|A cell]]'));

      final docx = _zip({
        'word/document.xml': utf8.encode(
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>'
          '<w:p><w:r><w:t>Before the figure.</w:t></w:r></w:p>'
          '<w:p><w:r><w:drawing><wp:inline><wp:docPr id="1" name="Pic" descr="Neuron diagram"/>'
          '<a:graphic><a:graphicData><a:blip r:embed="rId9"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
          '<w:p><w:r><w:t>After the figure.</w:t></w:r></w:p></w:body></w:document>',
        ),
        'word/_rels/document.xml.rels': utf8.encode(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId9" Type="image" Target="media/image1.png"/></Relationships>',
        ),
        'word/media/image1.png': png,
      });
      final d = await DocxExtractor().extract(docx, fileName: 'd.docx');
      expect(d.images.single.id, 'img1');
      expect(d.text, contains('[[img:img1|Neuron diagram]]'));
      expect(d.text.indexOf('Before'), lessThan(d.text.indexOf('[[img:img1')));
    });

    test('import stores figure files and links them to sections', () async {
      final dir = await Directory.systemTemp.createTemp('unrot_fig');
      final library = LibraryRepository(JsonStore(dir));
      final service = IngestionService(library, allowPdfSystemFallback: false);
      final document = pw.Document()
        ..addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                pw.Text('Figures make abstract ideas concrete and help learners remember them.'),
                pw.Image(pw.MemoryImage(File('test/fixtures/figure.jpg').readAsBytesSync()), width: 160),
                pw.Text('Figure 7: Sunset'),
              ],
            ),
          ),
        );
      final result = await service.importFile(await document.save(), 'figures.pdf');
      final images = result.chunks.expand((c) => c.images).toList();
      expect(images.single.caption, 'Figure 7: Sunset');
      final file = library.imageFile(result.source.id, images.single.id)!;
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync().sublist(0, 2), [0xFF, 0xD8]);
      await library.removeSource(result.source.id);
      expect(file.existsSync(), isFalse);
    });

    test('png encoder produces a valid header', () {
      final png = _png(10, 10);
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
    });
  });
}
