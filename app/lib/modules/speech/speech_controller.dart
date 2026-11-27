import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/reel.dart';
import '../../core/models/settings.dart';
import 'speech_engine.dart';
import 'speech_script.dart';

/// Reads reels aloud and remembers which reel is being read.
///
/// * [play] reads the visible part of a reel. In hands-free mode it then waits
///   a few seconds for an answer and reads the solution, so the feed can move
///   on by itself.
/// * [onAnswered] reads the solution after the learner answered a reel that is
///   (or was just) being read.
class SpeechController extends ChangeNotifier {
  SpeechController(this.engine, {required this.settings});

  final SpeechEngine engine;

  /// Current audio settings (read on every use, so changes apply at once).
  final AudioSettings Function() settings;

  /// How long hands-free mode waits for an answer before reading the solution.
  Duration thinkTime = const Duration(seconds: 6);

  bool? _available;
  String? _speakingId;
  String? _activeId;
  int _token = 0;
  bool _interrupted = false;
  bool? _answer;
  bool _rated = false;
  Completer<void>? _signal;

  /// null until checked.
  bool? get available => _available;

  /// Id of the reel that is being read (or whose answer is awaited).
  String? get speakingId => _speakingId;
  bool isSpeaking(String reelId) => _speakingId == reelId;

  Future<bool> checkAvailable() async {
    if (_available != null) return _available!;
    try {
      _available = await engine.isAvailable();
    } catch (_) {
      _available = false;
    }
    notifyListeners();
    return _available!;
  }

  /// Toggles reading [reel] (rail button).
  Future<void> toggle(Reel reel) async {
    if (isSpeaking(reel.id)) {
      await stop();
    } else {
      await play(reel);
    }
  }

  /// Reads [reel]; returns true when it was read to the end (not stopped).
  Future<bool> play(Reel reel, {bool handsFree = false}) async {
    final token = ++_token;
    await engine.stop();
    if (!await checkAvailable() || token != _token) return false;
    final language = SpeechScript.languageCode(reel);
    _activeId = reel.id;
    _answer = null;
    _rated = false;
    _interrupted = false;
    _signal = Completer<void>();
    _setSpeaking(reel.id);
    try {
      await _say(SpeechScript.forReel(reel), language);
      if (token != _token) return false;
      _interrupted = false;
      if (SpeechScript.answerFor(reel) == null || _rated) return true;
      if (_answer == null && handsFree) {
        // Give the learner a moment to answer, then say the solution.
        await _signal!.future.timeout(thinkTime, onTimeout: () {});
        if (token != _token) return false;
      }
      if (_rated || (_answer == null && !handsFree)) return true;
      if (!settings().readAnswers && _answer != null) return true;
      await _say(SpeechScript.answerFor(reel, correct: _answer)!, language);
      return token == _token;
    } finally {
      if (token == _token) _setSpeaking(null);
    }
  }

  /// The learner answered [reel]: reads the solution if audio is on for it.
  void onAnswered(Reel reel, bool correct) {
    if (_activeId != reel.id) return;
    if (_speakingId == reel.id) {
      // Still reading the question (or waiting): jump to the solution.
      _answer = correct;
      _interrupt();
    } else if (settings().readAnswers) {
      unawaited(_readAnswer(reel, correct));
    }
  }

  /// The learner revealed and rated a recall card: no need to read the back.
  void onRated(Reel reel) {
    if (_activeId != reel.id || _speakingId != reel.id) return;
    _rated = true;
    _interrupt();
  }

  Future<void> _readAnswer(Reel reel, bool correct) async {
    final text = SpeechScript.answerFor(reel, correct: correct);
    if (text == null) return;
    final token = ++_token;
    await engine.stop();
    if (token != _token) return;
    _setSpeaking(reel.id);
    try {
      await _say(text, SpeechScript.languageCode(reel));
    } finally {
      if (token == _token) _setSpeaking(null);
    }
  }

  void _interrupt() {
    _interrupted = true;
    final s = _signal;
    if (s != null && !s.isCompleted) s.complete();
    unawaited(engine.stop());
  }

  Future<void> _say(String text, String language) async {
    if (text.trim().isEmpty || _interrupted) return;
    try {
      await engine.speak(text, languageCode: language, rate: settings().rate);
    } catch (e) {
      debugPrint('Speech failed: $e');
    }
  }

  /// Stops reading.
  Future<void> stop() async {
    _token++;
    _activeId = null;
    final s = _signal;
    if (s != null && !s.isCompleted) s.complete();
    _setSpeaking(null);
    await engine.stop();
  }

  void _setSpeaking(String? id) {
    if (_speakingId == id) return;
    _speakingId = id;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
