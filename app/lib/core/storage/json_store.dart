import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Minimal document store that persists JSON files below [directory].
///
/// * Writes are atomic (temp file + rename) and serialised per file.
/// * [scheduleWrite] debounces frequent updates (e.g. progress after every swipe).
///
/// This is intentionally tiny so it can later be swapped for SQLite/Drift or a
/// sync backend without touching the repositories' public API.
class JsonStore {
  JsonStore(this.directory);

  final Directory directory;
  final Map<String, Timer> _timers = {};
  final Map<String, Object? Function()> _pendingBuilders = {};
  final Map<String, Future<void>> _writeChains = {};

  File _file(String name) => File(p.join(directory.path, name));

  Future<Object?> read(String name) async {
    final file = _file(name);
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on FormatException {
      // Corrupted file: keep a copy for debugging and start fresh.
      try {
        await file.copy('${file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(String name, Object? value) {
    _timers.remove(name)?.cancel();
    _pendingBuilders.remove(name);
    final encoded = jsonEncode(value);
    final previous = _writeChains[name] ?? Future.value();
    final next = previous.then((_) => _writeAtomic(name, encoded));
    _writeChains[name] = next.catchError((_) {});
    return next;
  }

  Future<void> _writeAtomic(String name, String contents) async {
    final file = _file(name);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }

  /// Debounced write: [build] is evaluated when the write actually happens.
  void scheduleWrite(String name, Object? Function() build, {Duration delay = const Duration(milliseconds: 500)}) {
    _pendingBuilders[name] = build;
    _timers[name]?.cancel();
    _timers[name] = Timer(delay, () {
      final builder = _pendingBuilders.remove(name);
      _timers.remove(name);
      if (builder != null) write(name, builder());
    });
  }

  /// Writes every pending debounced document immediately.
  Future<void> flush() async {
    final pending = Map.of(_pendingBuilders);
    for (final name in pending.keys) {
      _timers.remove(name)?.cancel();
    }
    _pendingBuilders.clear();
    await Future.wait([for (final e in pending.entries) write(e.key, e.value())]);
    await Future.wait(_writeChains.values);
  }

  Future<void> delete(String name) async {
    _timers.remove(name)?.cancel();
    _pendingBuilders.remove(name);
    await (_writeChains[name] ?? Future.value());
    final file = _file(name);
    if (await file.exists()) await file.delete();
  }

  Future<List<String>> list(String subdirectory) async {
    final dir = Directory(p.join(directory.path, subdirectory));
    if (!await dir.exists()) return [];
    return [
      await for (final entity in dir.list())
        if (entity is File && entity.path.endsWith('.json')) p.join(subdirectory, p.basename(entity.path)),
    ];
  }
}
