import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech backend. Implementations: platform TTS ([FlutterTtsEngine])
/// on Android/iOS/macOS/Windows and system commands ([CommandSpeechEngine])
/// on Linux. Cloud voices can be added by implementing this interface.
abstract class SpeechEngine {
  /// Human readable name shown in Settings.
  String get name;

  Future<bool> isAvailable();

  /// Speaks [text]; the future completes when speaking finished or was stopped.
  Future<void> speak(String text, {required String languageCode, double rate = 1.0});

  Future<void> stop();

  /// Picks the engine for the current platform.
  static SpeechEngine forPlatform() => Platform.isLinux ? CommandSpeechEngine() : FlutterTtsEngine();
}

/// Platform speech synthesis via `flutter_tts`.
class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine();

  FlutterTts? _tts;
  Completer<void>? _done;

  FlutterTts get tts {
    var t = _tts;
    if (t == null) {
      t = _tts = FlutterTts();
      // Completion is tracked with the handlers: whether `speak` itself waits
      // (and returns on cancel) differs between platforms.
      t.setCompletionHandler(_finish);
      t.setCancelHandler(_finish);
      t.setErrorHandler((_) => _finish());
      if (Platform.isIOS) {
        // Audible with the silent switch on; lowers other audio while speaking.
        unawaited(
          t
              .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, const [
                IosTextToSpeechAudioCategoryOptions.duckOthers,
              ], IosTextToSpeechAudioMode.spokenAudio)
              .catchError((_) {}),
        );
      }
    }
    return t;
  }

  void _finish() {
    final d = _done;
    _done = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  @override
  String get name => 'System voice';

  @override
  Future<bool> isAvailable() async {
    try {
      await tts.awaitSpeakCompletion(false);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text, {required String languageCode, double rate = 1.0}) async {
    _finish();
    try {
      await tts.setLanguage(languageCode);
    } catch (_) {}
    // iOS/macOS/Windows use 0.5 as normal speed, Android 1.0.
    await tts.setSpeechRate(Platform.isAndroid ? rate : (0.5 * rate).clamp(0.1, 1.0));
    final done = _done = Completer<void>();
    final result = await tts.speak(text);
    if (result == 0) _finish(); // could not start
    await done.future;
  }

  @override
  Future<void> stop() async {
    _finish();
    try {
      await tts.stop();
    } catch (_) {}
  }
}

typedef ProcessStarter = Future<Process> Function(String executable, List<String> arguments);
typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// Linux: `espeak-ng` (or `espeak`) or speech-dispatcher's `spd-say`.
class CommandSpeechEngine implements SpeechEngine {
  CommandSpeechEngine({ProcessStarter? start, ProcessRunner? run})
    : _start = start ?? ((e, a) => Process.start(e, a)),
      _run = run ?? ((e, a) => Process.run(e, a));

  /// Tried in this order. espeak is preferred because stopping it is reliable
  /// and does not interfere with other speech-dispatcher clients (screen readers).
  static const tools = ['espeak-ng', 'espeak', 'spd-say'];

  final ProcessStarter _start;
  final ProcessRunner _run;
  String? _tool;
  Process? _process;
  Future<void> _stopping = Future.value();

  /// The detected command (null until [isAvailable] found one).
  String? get tool => _tool;

  @override
  String get name => switch (_tool) {
    'spd-say' => 'speech-dispatcher (spd-say)',
    'espeak-ng' => 'eSpeak NG',
    'espeak' => 'eSpeak',
    _ => 'none found',
  };

  @override
  Future<bool> isAvailable() async {
    if (_tool != null) return true;
    for (final tool in tools) {
      try {
        final r = await _run(tool, const ['--version']);
        if (r.exitCode == 0) {
          _tool = tool;
          return true;
        }
      } catch (_) {
        // not installed
      }
    }
    return false;
  }

  /// Command line for [text] (exposed for tests).
  List<String> arguments(String text, String languageCode, double rate) {
    final lang = languageCode.split(RegExp('[-_]')).first.toLowerCase();
    if (_tool == 'spd-say') {
      // -w waits until speaking finished; rate is -100..100.
      final spdRate = ((rate - 1) * 100).round().clamp(-100, 100);
      return ['-w', '-l', lang, '-r', '$spdRate', '--', text];
    }
    return ['-v', lang, '-s', '${(165 * rate).round().clamp(80, 450)}', '--', text];
  }

  @override
  Future<void> speak(String text, {required String languageCode, double rate = 1.0}) async {
    if (!await isAvailable()) return;
    await stop();
    final process = await _start(_tool!, arguments(text, languageCode, rate));
    _process = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    await process.exitCode;
    if (identical(_process, process)) _process = null;
  }

  @override
  Future<void> stop() {
    final p = _process;
    _process = null;
    if (p == null) return _stopping;
    p.kill();
    if (_tool == 'spd-say') {
      // Killing spd-say does not always silence the daemon. Cancels run one
      // after another so a late cancel cannot cut off the next utterance.
      _stopping = _stopping.then((_) async {
        try {
          await _run('spd-say', const ['-C']);
        } catch (_) {}
      });
    }
    return _stopping;
  }
}

/// Engine that never speaks (tests, unsupported platforms).
class SilentSpeechEngine implements SpeechEngine {
  final List<String> spoken = [];

  @override
  String get name => 'silent';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> speak(String text, {required String languageCode, double rate = 1.0}) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}
