import 'dart:io';

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:unrot/app/app.dart';
import 'package:unrot/app/app_services.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/core/storage/secret_store.dart';
import 'package:unrot/modules/reels/reel_types.dart';
import 'package:unrot/modules/speech/speech_engine.dart';
import 'package:unrot/modules/study/progress_tracker.dart';
import 'package:unrot/ui/reels/math_reels.dart';
import 'package:unrot/ui/reels/reel_common.dart';
import 'package:unrot/ui/reels/reel_widgets.dart';
import 'package:unrot/ui/screens/settings_screen.dart';
import 'package:unrot/ui/theme/app_theme.dart';

class Recorder {
  final answers = <bool>[];
  final ratings = <RecallRating>[];
}

var _id = 0;

Reel mathReel(String type, Map<String, dynamic> raw) => Reel(
  id: 'm${_id++}',
  sourceId: 's',
  chunkId: 's:d1-0',
  type: type,
  data: ReelTypes.byId(type)!.normalize(raw)!,
  createdAt: DateTime(2026),
);

ReelContext contextFor(Reel reel, Recorder rec) => ReelContext(
  reel: reel,
  onAnswer: rec.answers.add,
  onRate: rec.ratings.add,
  pen: PenSettings(),
  annotations: AnnotationRepository(JsonStore(Directory.systemTemp.createTempSync('unrot_mw'))),
  memory: {},
);

Future<Recorder> pumpReel(WidgetTester tester, Reel reel) async {
  tester.view.physicalSize = const Size(520, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rec = Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.indigo,
        body: SingleChildScrollView(child: SizedBox(width: 480, child: ReelWidgets.body(contextFor(reel, rec)))),
      ),
    ),
  );
  await tester.pump();
  return rec;
}

void main() {
  test('units are shown as plain text', () {
    expect(unitLabel(r'\Omega'), 'Ω');
    expect(unitLabel(r'\mathrm{k\Omega}'), 'kΩ');
    expect(unitLabel(r'\mu F'), 'µ F');
    expect(unitLabel('m^2'), 'm²');
    expect(unitLabel(r'\mathrm{cm}^{-3}'), 'cm⁻³');
    expect(unitLabel(r'^\circ C'), '° C');
    expect(unitLabel('V'), 'V');
  });

  testWidgets('math recipe reveals steps one by one', (tester) async {
    await pumpReel(
      tester,
      mathReel('math_recipe', {
        'title': 'Partialbruchzerlegung',
        'goal': 'Rationale Funktion in einfache Brüche zerlegen',
        'steps': [
          {'action': 'Nenner faktorisieren', 'latex': 'x^2-1=(x-1)(x+1)'},
          {'action': 'Ansatz aufstellen', 'latex': r'\frac{A}{x-1}+\frac{B}{x+1}'},
          {'action': 'Koeffizienten vergleichen', 'latex': ''},
        ],
        'example': {
          'problem': r'$\frac{2}{x^2-1}$',
          'steps': ['A = 1', 'B = -1'],
          'result': r'$\frac{1}{x-1}-\frac{1}{x+1}$',
        },
        'pitfalls': ['Grad des Zählers prüfen'],
      }),
    );
    expect(find.text('Partialbruchzerlegung'), findsOneWidget);
    expect(find.textContaining('Nenner faktorisieren'), findsOneWidget);
    expect(find.textContaining('Ansatz aufstellen'), findsNothing);
    await tester.tap(find.text('Step 2 of 3'));
    await tester.pump();
    expect(find.textContaining('Ansatz aufstellen'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    await tester.pump();
    expect(find.textContaining('Koeffizienten vergleichen'), findsOneWidget);
    expect(find.text('WORKED EXAMPLE'), findsNothing);
    await tester.tap(find.text('Worked example'));
    await tester.pump();
    expect(find.text('WORKED EXAMPLE'), findsOneWidget);
    expect(find.byType(Math), findsWidgets);
  });

  testWidgets('theorem hides the statement until tapped, then asks for a rating', (tester) async {
    final rec = await pumpReel(
      tester,
      mathReel('theorem', {
        'kind': 'Satz',
        'name': 'Satz von Rolle',
        'assumptions': [r'$f$ stetig auf $[a,b]$', r'$f(a) = f(b)$'],
        'statement': r'Es gibt ein $\xi \in (a,b)$ mit $f^\prime(\xi) = 0$.',
        'formula': r"f'(\xi) = 0",
        'intuition': 'Zwischen zwei gleich hohen Punkten gibt es eine waagrechte Tangente.',
        'proof_idea': 'Extremwert im Inneren annehmen.',
        'example': r'$f(x) = x^2$ auf $[-1,1]$.',
      }),
    );
    expect(find.text('Satz von Rolle'), findsOneWidget);
    expect(find.text('ASSUMPTIONS'), findsOneWidget);
    expect(find.text('STATEMENT'), findsNothing);
    await tester.tap(find.textContaining('tap to reveal'));
    await tester.pump();
    expect(find.text('STATEMENT'), findsOneWidget);
    await tester.tap(find.text('💡 Intuition'));
    await tester.pump();
    expect(find.textContaining('waagrechte Tangente'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pump();
    expect(rec.ratings, [RecallRating.good]);
  });

  testWidgets('formula card reveals symbol meanings', (tester) async {
    await pumpReel(
      tester,
      mathReel('formula', {
        'name': 'Ohmsches Gesetz',
        'latex': r'U = R \cdot I',
        'symbols': [
          {'symbol': 'U', 'meaning': 'Spannung', 'unit': 'V'},
          {'symbol': 'R', 'meaning': 'Widerstand', 'unit': r'\Omega'},
          {'symbol': 'I', 'meaning': 'Strom', 'unit': 'A'},
        ],
        'conditions': 'Ohmscher Leiter',
      }),
    );
    expect(find.text('Ohmsches Gesetz'), findsOneWidget);
    expect(find.text('tap to reveal'), findsNWidgets(3));
    await tester.tap(find.text('tap to reveal').first);
    await tester.pump();
    expect(find.textContaining('Spannung'), findsOneWidget);
    await tester.tap(find.text('Reveal all'));
    await tester.pump();
    expect(find.text('tap to reveal'), findsNothing);
    expect(find.textContaining('Widerstand'), findsOneWidget);
  });

  testWidgets('calculation exercise checks numeric answers with tolerance', (tester) async {
    final reel = mathReel('calc_exercise', {
      'problem': r'Ein Widerstand $R = 50\,\Omega$ liegt an $U = 10\,V$. Berechne den Strom.',
      'given': [
        {'symbol': 'U', 'value': '10', 'unit': 'V'},
        {'symbol': 'R', 'value': '50', 'unit': r'\Omega'},
      ],
      'asked': 'I',
      'answer': 0.2,
      'unit': 'A',
      'tolerance': 0.02,
      'hint': r'$I = U / R$',
      'solution': [r'$I = U/R = 10/50 = 0.2\,A$'],
    });
    final rec = await pumpReel(tester, reel);
    expect(find.text('GIVEN'), findsOneWidget);
    expect(find.text('50 Ω'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Check'));
    await tester.pump();
    expect(find.textContaining('Enter a number'), findsOneWidget);
    expect(rec.answers, isEmpty);
    await tester.enterText(find.byType(TextField), '0,201');
    await tester.tap(find.text('Check'));
    await tester.pump();
    expect(rec.answers, [true]);
    expect(find.text('SOLUTION'), findsOneWidget);

    final rec2 = await pumpReel(tester, mathReel('calc_exercise', reel.data));
    await tester.enterText(find.byType(TextField), '2e-1 * 2');
    await tester.tap(find.text('Check'));
    await tester.pump();
    expect(rec2.answers, [false]);
    expect(find.text('SOLUTION'), findsOneWidget);
  });

  testWidgets('math-heavy reels use the neutral background; reruns are marked', (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reel = mathReel('formula', {
      'name': 'Euler',
      'latex': r'e^{i\pi} + 1 = 0',
      'symbols': <Map<String, String>>[],
    });
    Future<void> pumpPage({required bool neutral, bool rerun = false, Reel? r}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelPage(
            ctx: contextFor(r ?? reel, Recorder()),
            source: null,
            chunk: null,
            isReview: false,
            isRerun: rerun,
            neutralBackground: neutral,
          ),
        ),
      ),
    );
    bool hasGraphPaper() =>
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is GraphPaperPainter).evaluate().isNotEmpty;
    List<Color>? gradient() {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(ReelPage), matching: find.byType(DecoratedBox)).first,
      );
      return ((box.decoration as BoxDecoration).gradient as LinearGradient?)?.colors;
    }

    await pumpPage(neutral: true, rerun: true);
    expect(hasGraphPaper(), isTrue);
    expect(gradient(), AppTheme.neutralGradient);
    expect(find.text('Seen before'), findsOneWidget);

    await pumpPage(neutral: false);
    expect(hasGraphPaper(), isFalse);
    expect(find.text('Seen before'), findsNothing);

    final plain = Reel(
      id: 'p',
      sourceId: 's',
      chunkId: 's:d1-0',
      type: 'explainer',
      data: {'title': 'Cells', 'body': 'Cells are small.'},
      createdAt: DateTime(2026),
    );
    await pumpPage(neutral: true, r: plain);
    expect(hasGraphPaper(), isFalse);
  });

  testWidgets('feed: Listen reads the current reel, headphones turn on hands-free', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = SilentSpeechEngine();
    final services = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('unrot_listen');
      final s = await AppServices.create(directory: dir, secrets: MemorySecretStore(), speechEngine: engine);
      await s.ingestion.importText(
        'Cells',
        '## Membranes\n\nThe cell membrane is a selectively permeable barrier made of a phospholipid bilayer. '
            'Proteins embedded in the membrane act as channels and receptors. Oxygen diffuses directly through it.',
      );
      return s;
    }))!;
    await tester.pumpWidget(UnRotApp(services: services));
    await tester.runAsync(() => services.feed.ensureBuffer(force: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Listen'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(engine.spoken, hasLength(1));
    expect(engine.spoken.single, isNotEmpty);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Hands-free: read reels aloud'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(services.settings.settings.audio.autoRead, isTrue);
    expect(engine.spoken.length, greaterThanOrEqualTo(2));
    expect(find.byTooltip('Stop reading aloud'), findsOneWidget);

    // Settings show the audio section.
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('Audio'),
      300,
      scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.pump();
    expect(find.text('Voice: silent'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    // Let debounced saves fire (their file IO completes outside the fake clock).
    await tester.pump(const Duration(seconds: 2));
  });
}
