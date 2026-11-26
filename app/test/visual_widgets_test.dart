import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/modules/ingestion/extractors/png_encoder.dart';
import 'package:unrot/modules/study/progress_tracker.dart';
import 'package:unrot/modules/visuals/visual_spec.dart';
import 'package:unrot/ui/reels/reel_common.dart';
import 'package:unrot/ui/reels/reel_widgets.dart';
import 'package:unrot/ui/visuals/controls.dart';
import 'package:unrot/ui/visuals/plot.dart';
import 'package:unrot/ui/visuals/svg_view.dart';
import 'package:unrot/ui/widgets/rich_text.dart';

class Recorder {
  final answers = <bool>[];
  final ratings = <RecallRating>[];
}

var _nextId = 0;

Reel visualReel(Map<String, dynamic> raw) => Reel(
  id: 'v${_nextId++}',
  sourceId: 's',
  chunkId: 's:0',
  type: 'visual',
  data: VisualNormalizer.normalize(raw)!,
  createdAt: DateTime(2026),
);

Future<Recorder> pumpReel(WidgetTester tester, Reel reel, {File? Function(String, String)? imageFile}) async {
  tester.view.physicalSize = const Size(520, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rec = Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.indigo,
        body: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: ReelWidgets.body(
              ReelContext(
                reel: reel,
                onAnswer: rec.answers.add,
                onRate: rec.ratings.add,
                pen: PenSettings(),
                annotations: AnnotationRepository(JsonStore(Directory.systemTemp.createTempSync('unrot_vw'))),
                memory: {},
                imageFile: imageFile,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return rec;
}

void main() {
  testWidgets('function plot with slider and challenge', (tester) async {
    final rec = await pumpReel(
      tester,
      visualReel({
        'title': 'Parabolas',
        'caption': r'The sign of $a$ decides the direction.',
        'visual': {
          'kind': 'function_plot',
          'x_min': -3,
          'x_max': 3,
          'functions': [
            {'expr': 'a*x^2', 'label': 'f(x)'},
          ],
        },
        'controls': [
          {'kind': 'slider', 'param': 'a', 'label': 'Opening a', 'min': -2, 'max': 2, 'step': 0.5, 'value': 1},
        ],
        'challenge': {
          'prompt': 'Make the parabola open downwards',
          'condition': 'a < 0',
          'success': 'Yes! a < 0 flips it.',
        },
      }),
    );
    expect(find.byType(FunctionPlot), findsOneWidget);
    expect(find.text('Opening a'), findsOneWidget);
    expect(find.byType(Math), findsWidgets, reason: r'$a$ in the caption is rendered as math');
    expect(find.text('🎯'), findsOneWidget);
    expect(rec.answers, isEmpty);

    // Drag the slider to the far left (a = -2).
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pump();
    expect(rec.answers, [true]);
    expect(find.text('✅'), findsOneWidget);
    expect(find.text('Yes! a < 0 flips it.'), findsOneWidget);

    // Tapping the plot shows a readout; nothing crashes.
    await tester.tap(find.byType(FunctionPlot));
    await tester.pump();

    // Reset restores the initial value; the challenge stays solved (answered once).
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('1'), findsWidgets);
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pump();
    expect(rec.answers, [true]);
    await tester.pump(const Duration(seconds: 1)); // double-tap timer of the plot
  });

  testWidgets('dial, toggle, buttons and stepper change parameters', (tester) async {
    await pumpReel(
      tester,
      visualReel({
        'visual': {
          'kind': 'chart',
          'chart_type': 'bar',
          'labels': ['A', 'B'],
          'series': [
            {
              'name': 'S',
              'values': ['k*n', 'r*show'],
            },
          ],
        },
        'controls': [
          {'kind': 'dial', 'param': 'r', 'label': 'Rate', 'min': 0, 'max': 10, 'value': 5},
          {'kind': 'toggle', 'param': 'show', 'label': 'Show B', 'value': 0},
          {
            'kind': 'buttons',
            'param': 'k',
            'label': 'Factor',
            'options': [
              {'label': 'x1', 'value': 1},
              {'label': 'x3', 'value': 3},
            ],
          },
          {'kind': 'stepper', 'param': 'n', 'label': 'Count', 'min': 1, 'max': 4, 'value': 2},
        ],
      }),
    );
    expect(find.byType(Dial), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    // Tap the right side of the dial: value becomes clearly above the middle.
    final dial = tester.getRect(find.byType(Dial).first);
    await tester.tapAt(Offset(dial.center.dx + 30, dial.top + 42));
    await tester.pump();
    expect(find.text('5'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('x3'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'x3')).selected, isTrue);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('3'), findsWidgets);
    await tester.pump(const Duration(seconds: 1)); // chart intro animation
  });

  testWidgets('equation steps are revealed one by one', (tester) async {
    await pumpReel(
      tester,
      visualReel({
        'visual': {
          'kind': 'equation',
          'latex': r'a^2 + b^2 = c^2',
          'steps': [
            {'latex': r'c^2 = 3^2 + 4^2', 'note': 'Insert the legs'},
            {'latex': r'c = 5', 'note': 'Take the root'},
          ],
        },
      }),
    );
    expect(find.text('Insert the legs'), findsNothing);
    await tester.tap(find.text('Step 1 of 2'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Insert the legs'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Take the root'), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(3));
  });

  testWidgets('animation plays, pauses and drives the time variable', (tester) async {
    await pumpReel(
      tester,
      visualReel({
        'visual': {
          'kind': 'function_plot',
          'functions': ['sin(x - t)'],
        },
        'animate': {'param': 't', 'from': 0, 'to': 6.28, 'seconds': 2},
      }),
    );
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, greaterThan(0.1));
    await tester.tap(find.byIcon(Icons.pause_circle));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
  });

  testWidgets('figures from the source are shown', (tester) async {
    final dir = Directory.systemTemp.createTempSync('unrot_img');
    final random = Random(3);
    final file = File('${dir.path}/img1.png')
      ..writeAsBytesSync(
        encodePng(40, 30, 3, Uint8List.fromList(List.generate(40 * 30 * 3, (_) => random.nextInt(256)))),
      );
    await pumpReel(
      tester,
      visualReel({
        'caption': 'Figure 1: noise',
        'visual': {'kind': 'image', 'image_id': 'img1', 'alt': 'Noise'},
      }),
      imageFile: (sourceId, id) => id == 'img1' ? file : null,
    );
    expect(find.byType(Image), findsOneWidget);
    await pumpReel(
      tester,
      visualReel({
        'visual': {'kind': 'image', 'image_url': 'https://example.org/a.png', 'alt': 'Web'},
      }),
    );
    expect(find.textContaining('Web images are turned off'), findsOneWidget);
  });

  testWidgets('svg diagrams render', (tester) async {
    await pumpReel(
      tester,
      visualReel({
        'visual': {
          'kind': 'diagram',
          'svg': "<svg viewBox='0 0 100 60'><circle cx='{{20 + 10*p}}' cy='30' r='10' fill='#FFD54F'/></svg>",
        },
        'controls': [
          {'param': 'p', 'min': 0, 'max': 5, 'value': 1},
        ],
      }),
    );
    expect(find.byType(LiveSvg), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('This sketch could not be drawn.'), findsNothing);
  });

  testWidgets('markup renders inline and display math', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkupText(r'The **area** is $\pi r^2$ and $$\int_0^1 x\,dx = \frac12$$ — costs $5 and $10.'),
        ),
      ),
    );
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'costs $5 and $10', findRichText: true), findsOneWidget);
  });
}
