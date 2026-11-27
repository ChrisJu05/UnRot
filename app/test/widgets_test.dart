import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:unrot/app/app.dart';
import 'package:unrot/app/app_services.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/core/storage/secret_store.dart';
import 'package:unrot/modules/speech/speech_engine.dart';
import 'package:unrot/modules/study/progress_tracker.dart';
import 'package:unrot/ui/pen/pen_canvas.dart';
import 'package:unrot/ui/reels/reel_common.dart';
import 'package:unrot/ui/reels/reel_widgets.dart';

class Recorder {
  final answers = <bool>[];
  final ratings = <RecallRating>[];
}

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.indigo,
    body: SingleChildScrollView(
      child: Center(child: SizedBox(width: 480, child: child)),
    ),
  ),
);

ReelContext ctxFor(Reel reel, Recorder rec, {PenSettings? pen}) => ReelContext(
  reel: reel,
  onAnswer: rec.answers.add,
  onRate: rec.ratings.add,
  pen: pen ?? PenSettings(),
  annotations: AnnotationRepository(JsonStore(Directory.systemTemp.createTempSync('unrot_ann'))),
  memory: {},
);

Reel reel(String type, Map<String, dynamic> data) =>
    Reel(id: 'r-$type', sourceId: 's', chunkId: 's:0', type: type, data: data, createdAt: DateTime(2026));

void main() {
  group('Reel widgets', () {
    testWidgets('quiz: answer once, show feedback', (tester) async {
      final rec = Recorder();
      final r = reel('quiz', {
        'question': 'What produces ATP?',
        'options': ['Nucleus', 'Mitochondrion', 'Ribosome', 'Golgi'],
        'answer_index': 1,
        'explanation': 'Cellular respiration happens there.',
      });
      await tester.pumpWidget(host(ReelWidgets.body(ctxFor(r, rec))));
      await tester.tap(find.text('Nucleus'));
      await tester.pumpAndSettle();
      expect(rec.answers, [false]);
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Cellular respiration happens there.'), findsOneWidget);
      await tester.tap(find.text('Mitochondrion'));
      await tester.pump();
      expect(rec.answers, [false], reason: 'only the first answer counts');
    });

    testWidgets('true/false', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(
        host(ReelWidgets.body(ctxFor(reel('true_false', {'statement': 'Cells have walls.', 'answer': false}), rec))),
      );
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();
      expect(rec.answers, [true]);
      expect(find.text('Correct!'), findsOneWidget);
    });

    testWidgets('cloze: typed answer with a small typo counts', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(
        host(
          ReelWidgets.body(ctxFor(reel('cloze', {'text': 'ATP is made in the ____.', 'answer': 'mitochondria'}), rec)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Mitochondira');
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(rec.answers, [true]);
    });

    testWidgets('flashcard: flip and self-rate', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(
        host(ReelWidgets.body(ctxFor(reel('flashcard', {'front': 'Osmosis?', 'back': 'Diffusion of water.'}), rec))),
      );
      expect(find.text('Osmosis?'), findsOneWidget);
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      expect(find.text('Diffusion of water.'), findsOneWidget);
      await tester.tap(find.text('Good'));
      await tester.pump();
      expect(rec.ratings, [RecallRating.good]);
    });

    testWidgets('write from memory: draw, compare, rate', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(
        host(
          ReelWidgets.body(
            ctxFor(
              reel('write_recall', {
                'prompt': 'Sketch the cell membrane',
                'model_answer': 'A phospholipid bilayer with proteins.',
                'key_terms': ['bilayer'],
              }),
              rec,
            ),
          ),
        ),
      );
      final canvas = find.byType(PenCanvas);
      expect(canvas, findsOneWidget);
      await tester.dragFrom(tester.getCenter(canvas), const Offset(80, 30), kind: PointerDeviceKind.stylus);
      await tester.pump();
      expect(find.textContaining('Write or sketch here'), findsNothing, reason: 'hint disappears after drawing');
      await tester.tap(find.text('Compare'));
      await tester.pumpAndSettle();
      expect(find.text('A phospholipid bilayer with proteins.'), findsOneWidget);
      await tester.tap(find.text('Hard'));
      expect(rec.ratings, [RecallRating.hard]);
      // Let the debounced annotation save fire.
      await tester.pump(const Duration(seconds: 1));
    });

    test('answersMatch is forgiving but not too forgiving', () {
      expect(answersMatch('the Mitochondria', 'mitochondria'), isTrue);
      expect(answersMatch('Zellkern', 'Zellkern.'), isTrue);
      expect(answersMatch('Groesse', 'Größe'), isTrue);
      expect(answersMatch('ribosome', 'mitochondria'), isFalse);
      expect(answersMatch('', 'x'), isFalse);
    });
  });

  group('PenCanvas', () {
    Future<PenController> pumpCanvas(WidgetTester tester, PenSettings settings, {bool fingers = true}) async {
      final controller = PenController();
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 300,
            child: PenCanvas(controller: controller, settings: settings, acceptFingersAndMouse: fingers),
          ),
        ),
      );
      return controller;
    }

    var nextPointer = 100;
    Future<void> stroke(
      WidgetTester tester,
      PointerDeviceKind kind, {
      double pressure = 0.5,
      int buttons = kPrimaryButton,
    }) async {
      final center = tester.getCenter(find.byType(PenCanvas));
      final id = nextPointer++;
      final gesture = await tester.createGesture(kind: kind, buttons: buttons, pointer: id);
      await gesture.downWithCustomEvent(
        center,
        PointerDownEvent(
          pointer: id,
          position: center,
          kind: kind,
          pressure: pressure,
          pressureMin: 0,
          pressureMax: 1,
          buttons: buttons,
        ),
      );
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(center + Offset(10.0 * i, 4.0 * i));
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('stylus draws with pressure', (tester) async {
      final pen = await pumpCanvas(tester, PenSettings());
      await stroke(tester, PointerDeviceKind.stylus, pressure: 0.9);
      expect(pen.strokes, hasLength(1));
      expect(pen.strokes.single.points.first.pressure, closeTo(0.9, 0.01));
      expect(pen.strokes.single.points.length, greaterThan(3));
    });

    testWidgets('palm rejection: stylus-only ignores touch', (tester) async {
      final pen = await pumpCanvas(tester, PenSettings(stylusOnly: true));
      await stroke(tester, PointerDeviceKind.touch);
      expect(pen.strokes, isEmpty);
      await stroke(tester, PointerDeviceKind.stylus);
      expect(pen.strokes, hasLength(1));
    });

    testWidgets('touch draws when allowed; overlay mode ignores touch', (tester) async {
      var pen = await pumpCanvas(tester, PenSettings());
      await stroke(tester, PointerDeviceKind.touch);
      expect(pen.strokes, hasLength(1));
      pen = await pumpCanvas(tester, PenSettings(), fingers: false);
      await stroke(tester, PointerDeviceKind.touch);
      expect(pen.strokes, isEmpty);
    });

    testWidgets('eraser end of the stylus removes strokes; undo/redo', (tester) async {
      final pen = await pumpCanvas(tester, PenSettings());
      await stroke(tester, PointerDeviceKind.stylus);
      await stroke(tester, PointerDeviceKind.invertedStylus);
      expect(pen.strokes, isEmpty);
      pen.undo();
      await stroke(tester, PointerDeviceKind.stylus);
      pen.undo();
      expect(pen.strokes, isEmpty);
      pen.redo();
      expect(pen.strokes, hasLength(1));
    });
  });

  group('App', () {
    testWidgets('smoke test: empty state, sample import, feed and tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('unrot_app');
        return AppServices.create(directory: dir, secrets: MemorySecretStore(), speechEngine: SilentSpeechEngine());
      }))!;
      await tester.pumpWidget(UnRotApp(services: services));
      await tester.runAsync(() => services.feed.ensureBuffer(force: true));
      await tester.pump();
      expect(find.text('Add your study material'), findsOneWidget);

      await tester.runAsync(() async {
        await services.ingestion.importText(
          'Cell Biology',
          '# Cells\n\n## Membranes\n\nThe cell membrane is a selectively permeable barrier made of a phospholipid bilayer. '
              'Proteins embedded in the membrane act as channels and receptors. Oxygen diffuses directly through the bilayer.\n\n'
              '## Mitochondria\n\nMitochondria produce ATP through cellular respiration. They have their own DNA, which supports '
              'the endosymbiotic theory. The inner membrane is folded into cristae.',
        );
        await services.feed.refresh();
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReelPage), findsWidgets);
      expect(find.text('Cell Biology'), findsWidgets);

      // Navigate with the keyboard.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(services.feed.currentIndex, 1);

      // Other tabs render.
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add material'), findsOneWidget);
      await tester.tap(find.text('Progress'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('day streak'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('AI provider'), findsOneWidget);

      // Let debounced saves fire (their file IO completes outside the fake clock).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('phone layout uses a bottom navigation bar', (tester) async {
      tester.view.physicalSize = const Size(400, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('unrot_phone');
        return AppServices.create(directory: dir, secrets: MemorySecretStore(), speechEngine: SilentSpeechEngine());
      }))!;
      await tester.pumpWidget(UnRotApp(services: services));
      await tester.pump();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.runAsync(services.flush);
    });
  });
}
