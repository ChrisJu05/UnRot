import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/modules/speech/speech_controller.dart';
import 'package:unrot/modules/speech/speech_engine.dart';
import 'package:unrot/modules/speech/speech_script.dart';

Reel reel(String type, Map<String, dynamic> data, {String? language = 'English'}) => Reel(
  id: 'r-$type',
  sourceId: 's',
  chunkId: 's:d0-0',
  type: type,
  data: data,
  createdAt: DateTime(2026),
  language: language,
);

/// Engine whose utterances last until [finish] or [stop] is called.
class HoldingEngine implements SpeechEngine {
  final List<String> spoken = [];
  final List<String> languages = [];
  Completer<void>? _current;
  bool available = true;

  bool get isSpeaking => _current != null && !_current!.isCompleted;

  void finish() => _current?.complete();

  @override
  String get name => 'holding';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> speak(String text, {required String languageCode, double rate = 1.0}) {
    spoken.add(text);
    languages.add(languageCode);
    final c = _current = Completer<void>();
    return c.future;
  }

  @override
  Future<void> stop() async {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete();
  }
}

/// Lets queued microtasks/timers run.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 5));

class FakeProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }

  void exit() => _exit.complete(0);

  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);
  @override
  int get pid => 1;
}

void main() {
  group('latexToSpeech', () {
    test('English', () {
      expect(SpeechScript.latexToSpeech(r'\frac{a}{b}'), 'a over b');
      expect(SpeechScript.latexToSpeech(r'x^2 + y^2 = r^2'), 'x squared plus y squared equals r squared');
      expect(SpeechScript.latexToSpeech(r'\sqrt{x}'), 'square root of x');
      expect(SpeechScript.latexToSpeech(r'\int_0^1 f(x)\,dx'), 'integral from 0 to 1 f(x) dx');
      expect(SpeechScript.latexToSpeech(r'\sum_{n=0}^{\infty} a_n'), contains('sum from n equals 0 to'));
      expect(SpeechScript.latexToSpeech(r'\alpha \leq \beta'), 'alpha less than or equal to beta');
      expect(SpeechScript.latexToSpeech(r'e^{-t}'), 'e to the power of minus t');
      expect(SpeechScript.latexToSpeech(r'\lim_{x \to 0} \frac{\sin x}{x} = 1'), contains('limit as x to 0'));
    });

    test('German', () {
      expect(SpeechScript.latexToSpeech(r'\frac{1}{2}', german: true), '1 durch 2');
      expect(SpeechScript.latexToSpeech(r'U = R \cdot I', german: true), 'U gleich R mal I');
      expect(SpeechScript.latexToSpeech(r'x^2', german: true), 'x Quadrat');
      expect(SpeechScript.latexToSpeech(r'\int_a^b', german: true), 'Integral von a bis b');
      expect(SpeechScript.latexToSpeech(r'\nabla \times \vec{E}', german: true), 'nabla mal Vektor E');
    });

    test('formatting commands keep their content', () {
      expect(SpeechScript.latexToSpeech(r'\mathrm{d}x'), 'd x');
      expect(SpeechScript.latexToSpeech(r'\left( a \right)'), '( a )');
    });
  });

  test('clean removes markdown and emojis and reads inline math', () {
    expect(SpeechScript.clean(r'**Ohm** 🔌 says $U = R I$.'), 'Ohm says U equals R I .');
  });

  test('languageCode uses the reel language or detects German', () {
    expect(SpeechScript.languageCode(reel('explainer', {'title': 'x'}, language: 'Deutsch')), 'de-DE');
    expect(SpeechScript.languageCode(reel('explainer', {'title': 'x'})), 'en-US');
    expect(
      SpeechScript.languageCode(
        reel('explainer', {
          'body': 'Die Spannung ist das Produkt aus Widerstand und Strom, wenn der Strom fließt.',
        }, language: 'source'),
      ),
      'de-DE',
    );
    expect(
      SpeechScript.languageCode(
        reel('explainer', {'body': 'The voltage is the product of the resistance and the current.'}, language: null),
      ),
      'en-US',
    );
  });

  group('forReel / answerFor', () {
    test('quiz reads question and options; answer names the right option', () {
      final r = reel('quiz', {
        'question': 'What is 2+2?',
        'options': ['3', '4'],
        'answer_index': 1,
        'explanation': 'Basic addition.',
      });
      expect(SpeechScript.forReel(r), 'What is 2+2? Option A: 3. Option B: 4.');
      expect(SpeechScript.answerFor(r, correct: true), 'Correct! The answer is B: 4. Basic addition.');
      expect(SpeechScript.answerFor(r), startsWith('The answer is B'));
    });

    test('flashcard reads the front, answer is the back', () {
      final r = reel('flashcard', {'front': 'Ohm\'s law?', 'back': r'$U = R I$'});
      expect(SpeechScript.forReel(r), "Ohm's law?");
      expect(SpeechScript.answerFor(r), 'U equals R I.');
    });

    test('cloze reads a blank and answers with the full sentence', () {
      final r = reel('cloze', {'text': 'The ____ produces ATP.', 'answer': 'mitochondrion'});
      expect(SpeechScript.forReel(r), 'The blank produces ATP.');
      expect(SpeechScript.answerFor(r), 'The mitochondrion produces ATP.');
    });

    test('theorem hides the statement until the answer', () {
      final r = reel('theorem', {
        'kind': 'Satz',
        'name': 'Mittelwertsatz',
        'assumptions': [r'$f$ stetig auf $[a,b]$', 'differenzierbar auf (a,b)'],
        'statement': r"Es gibt ein $\xi$ mit $f'(\xi) = \frac{f(b)-f(a)}{b-a}$.",
        'formula': '',
        'intuition': 'Irgendwo ist die Steigung gleich der mittleren Steigung.',
      }, language: 'Deutsch');
      final text = SpeechScript.forReel(r);
      expect(text, startsWith('Satz: Mittelwertsatz.'));
      expect(text, contains('Voraussetzungen'));
      expect(text, isNot(contains('Es gibt')));
      final answer = SpeechScript.answerFor(r, correct: false)!;
      expect(answer, startsWith('Nicht ganz.'));
      expect(answer, contains('durch'));
    });

    test('math recipe reads every step with formulas', () {
      final r = reel('math_recipe', {
        'title': 'Partialbruchzerlegung',
        'goal': 'Rationale Funktion zerlegen',
        'steps': [
          {'action': 'Nullstellen des Nenners bestimmen', 'latex': 'x^2 - 1 = 0'},
          {'action': 'Ansatz aufstellen', 'latex': r'\frac{A}{x-1} + \frac{B}{x+1}'},
        ],
      }, language: 'Deutsch');
      final text = SpeechScript.forReel(r);
      expect(text, contains('Schritt 1: Nullstellen des Nenners bestimmen.'));
      expect(text, contains('x Quadrat minus 1 gleich 0'));
      expect(text, contains('A durch x minus 1 plus B durch x plus 1'));
    });

    test('calc exercise answer reads the result in words', () {
      final r = reel('calc_exercise', {
        'problem': 'Compute the current.',
        'given': [
          {'symbol': 'U', 'value': '10', 'unit': 'V'},
          {'symbol': 'R', 'value': '5', 'unit': r'\Omega'},
        ],
        'asked': 'I',
        'answer': 2.0,
        'unit': 'A',
        'solution': [r'$I = U/R$'],
      });
      expect(SpeechScript.forReel(r), contains('Given: U equals 10 V; R equals 5 Omega'));
      expect(SpeechScript.answerFor(r), 'Result: 2 A. I equals U over R.');
      final big = reel('calc_exercise', {'problem': 'n?', 'answer': 1.5e16, 'unit': '', 'given': [], 'solution': []});
      expect(SpeechScript.answerFor(big), contains('1.5 times 10 to the power of 16'));
    });

    test('reels without a hidden part have no answer', () {
      expect(SpeechScript.answerFor(reel('explainer', {'title': 'T', 'body': 'B'})), isNull);
      expect(
        SpeechScript.forReel(reel('explainer', {'title': 'T', 'body': 'B', 'takeaway': 'K'})),
        'T. B. Key takeaway: K.',
      );
    });
  });

  group('CommandSpeechEngine', () {
    test('prefers espeak-ng and builds its command line', () async {
      final started = <List<String>>[];
      final processes = <FakeProcess>[];
      final engine = CommandSpeechEngine(
        run: (exe, args) async {
          if (exe == 'espeak-ng') return ProcessResult(1, 0, 'eSpeak NG 1.51', '');
          throw const ProcessException('x', []);
        },
        start: (exe, args) async {
          started.add([exe, ...args]);
          final p = FakeProcess();
          processes.add(p);
          return p;
        },
      );
      expect(await engine.isAvailable(), isTrue);
      expect(engine.tool, 'espeak-ng');
      expect(engine.name, 'eSpeak NG');
      final done = engine.speak('Hallo', languageCode: 'de-DE', rate: 1.2);
      await pump();
      expect(started.single, ['espeak-ng', '-v', 'de', '-s', '198', '--', 'Hallo']);
      // Stopping kills the running process and completes speak().
      await engine.stop();
      expect(processes.single.killed, isTrue);
      await done;
    });

    test('falls back to spd-say and cancels it on stop', () async {
      final runs = <String>[];
      final engine = CommandSpeechEngine(
        run: (exe, args) async {
          runs.add('$exe ${args.join(' ')}');
          if (exe == 'spd-say') return ProcessResult(1, 0, '', '');
          throw const ProcessException('x', []);
        },
        start: (exe, args) async => FakeProcess(),
      );
      expect(await engine.isAvailable(), isTrue);
      expect(engine.arguments('Hi', 'en-US', 1.5), ['-w', '-l', 'en', '-r', '50', '--', 'Hi']);
      final done = engine.speak('Hi', languageCode: 'en-US');
      await pump();
      await engine.stop();
      await done;
      expect(runs, contains('spd-say -C'));
    });

    test('reports unavailable when nothing is installed', () async {
      final engine = CommandSpeechEngine(
        run: (exe, args) async => throw const ProcessException('x', []),
        start: (exe, args) async => FakeProcess(),
      );
      expect(await engine.isAvailable(), isFalse);
      expect(engine.name, 'none found');
      await engine.speak('x', languageCode: 'en'); // no-op, no throw
    });

    test('espeak-ng synthesizes speech on this machine', () async {
      // Only runs where espeak-ng is installed; writes audio to stdout instead of a sound card.
      final which = await Process.run('which', ['espeak-ng']);
      if (which.exitCode != 0) return;
      final text = SpeechScript.latexToSpeech(r'\int_0^1 x^2 \, dx = \frac{1}{3}');
      final r = await Process.run('espeak-ng', ['-v', 'en', '--stdout', '--', text], stdoutEncoding: null);
      expect(r.exitCode, 0);
      expect((r.stdout as List<int>).length, greaterThan(10000));
      expect(utf8.decode((r.stdout as List<int>).take(4).toList()), 'RIFF');
    });
  });

  group('SpeechController', () {
    late HoldingEngine engine;
    late AudioSettings audio;
    late SpeechController speech;
    final quiz = reel('quiz', {
      'question': 'Q?',
      'options': ['a', 'b'],
      'answer_index': 0,
      'explanation': 'E.',
    });
    final explainer = reel('explainer', {'title': 'T', 'body': 'B'});

    setUp(() {
      engine = HoldingEngine();
      audio = AudioSettings();
      speech = SpeechController(engine, settings: () => audio)..thinkTime = const Duration(milliseconds: 40);
    });

    test('play reads a reel and reports completion', () async {
      final done = speech.play(explainer);
      await pump();
      expect(speech.isSpeaking(explainer.id), isTrue);
      expect(engine.spoken.single, 'T. B.');
      engine.finish();
      expect(await done, isTrue);
      expect(speech.speakingId, isNull);
    });

    test('stop interrupts and play returns false', () async {
      final done = speech.play(explainer);
      await pump();
      await speech.stop();
      expect(await done, isFalse);
      expect(speech.speakingId, isNull);
    });

    test('playing another reel cancels the first', () async {
      final first = speech.play(explainer);
      await pump();
      final second = speech.play(quiz);
      expect(await first, isFalse);
      await pump();
      expect(speech.isSpeaking(quiz.id), isTrue);
      engine.finish();
      expect(await second, isTrue);
    });

    test('hands-free: reads the solution when nobody answers', () async {
      final done = speech.play(quiz, handsFree: true);
      await pump();
      engine.finish(); // question read
      await Future<void>.delayed(const Duration(milliseconds: 80)); // think time passes
      expect(engine.spoken.last, startsWith('The answer is A'));
      engine.finish();
      expect(await done, isTrue);
    });

    test('answering during the question jumps to the feedback', () async {
      final done = speech.play(quiz, handsFree: true);
      await pump();
      speech.onAnswered(quiz, false);
      await pump();
      expect(engine.spoken.last, startsWith('Not quite. The answer is A'));
      engine.finish();
      expect(await done, isTrue);
    });

    test('manual listening reads the solution after a later answer', () async {
      final done = speech.play(quiz);
      await pump();
      engine.finish();
      expect(await done, isTrue);
      expect(engine.spoken, hasLength(1));
      speech.onAnswered(quiz, true);
      await pump();
      expect(engine.spoken.last, startsWith('Correct!'));
      engine.finish();
    });

    test('readAnswers off: no solution after answering', () async {
      audio.readAnswers = false;
      final done = speech.play(quiz, handsFree: true);
      await pump();
      speech.onAnswered(quiz, true);
      expect(await done, isTrue);
      expect(engine.spoken, hasLength(1));
    });

    test('rating a revealed card skips reading the back', () async {
      final card = reel('flashcard', {'front': 'F', 'back': 'B'});
      final done = speech.play(card, handsFree: true);
      await pump();
      engine.finish();
      await pump();
      speech.onRated(card);
      expect(await done, isTrue);
      expect(engine.spoken, ['F.']);
    });

    test('answers for reels that are not being read are ignored', () async {
      speech.onAnswered(quiz, true);
      await pump();
      expect(engine.spoken, isEmpty);
    });

    test('unavailable engine: play returns false', () async {
      engine.available = false;
      expect(await speech.play(explainer), isFalse);
      expect(speech.available, isFalse);
    });

    test('uses the reel language and the configured rate', () async {
      audio.rate = 1.5;
      final german = reel('explainer', {'title': 'Titel', 'body': 'Text'}, language: 'Deutsch');
      final done = speech.play(german);
      await pump();
      expect(engine.languages.single, 'de-DE');
      engine.finish();
      await done;
    });
  });

  test('AudioSettings round trip and clamping', () {
    final s = AppSettings.fromJson({
      'audio': {'autoRead': true, 'autoAdvance': true, 'rate': 9, 'readAnswers': false},
    });
    expect(s.audio.autoRead, isTrue);
    expect(s.audio.rate, 2.0);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.audio.autoAdvance, isTrue);
    expect(back.audio.readAnswers, isFalse);
    expect(AppSettings.fromJson({}).audio.rate, 1.0);
  });
}
