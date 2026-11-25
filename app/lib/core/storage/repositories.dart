import 'package:flutter/foundation.dart';

import '../models/annotation.dart';
import '../models/chunk.dart';
import '../models/progress.dart';
import '../models/reel.dart';
import '../models/source.dart';
import '../util/json.dart';
import 'json_store.dart';

/// Imported sources and their chunks.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository(this._store);

  final JsonStore _store;
  final List<StudySource> _sources = [];
  final Map<String, List<SourceChunk>> _chunks = {};

  List<StudySource> get sources => List.unmodifiable(_sources);

  StudySource? source(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<SourceChunk> chunks(String sourceId) => _chunks[sourceId] ?? const [];

  SourceChunk? chunk(String chunkId) {
    final sourceId = chunkId.split(':').first;
    for (final c in chunks(sourceId)) {
      if (c.id == chunkId) return c;
    }
    return null;
  }

  Future<void> load() async {
    final json = await _store.read('library.json');
    _sources
      ..clear()
      ..addAll(
        (json is Map ? (json['sources'] as List? ?? const []) : const []).map((e) => StudySource.fromJson(jMap(e))),
      );
    for (final s in _sources) {
      final chunkJson = await _store.read('chunks/${s.id}.json');
      _chunks[s.id] = (chunkJson is List ? chunkJson : const []).map((e) => SourceChunk.fromJson(jMap(e))).toList();
      s.chunkCount = _chunks[s.id]!.length;
    }
    notifyListeners();
  }

  Future<void> addSource(StudySource source, List<SourceChunk> chunks) async {
    source.chunkCount = chunks.length;
    source.charCount = chunks.fold(0, (sum, c) => sum + c.text.length);
    _sources.insert(0, source);
    _chunks[source.id] = chunks;
    await _store.write('chunks/${source.id}.json', chunks.map((c) => c.toJson()).toList());
    await _saveIndex();
    notifyListeners();
  }

  Future<void> updateSource(StudySource source) async {
    await _saveIndex();
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    _chunks.remove(id);
    await _store.delete('chunks/$id.json');
    await _saveIndex();
    notifyListeners();
  }

  Future<void> _saveIndex() => _store.write('library.json', {'sources': _sources.map((s) => s.toJson()).toList()});
}

/// Generated reels, persisted per source so they can be re-used for reviews.
class ReelRepository extends ChangeNotifier {
  ReelRepository(this._store);

  final JsonStore _store;
  final Map<String, Reel> _reels = {};

  Reel? reel(String id) => _reels[id];
  Iterable<Reel> get all => _reels.values;
  int get count => _reels.length;

  List<Reel> forChunk(String chunkId) => _reels.values.where((r) => r.chunkId == chunkId).toList();
  List<Reel> forSource(String sourceId) => _reels.values.where((r) => r.sourceId == sourceId).toList();

  Future<void> load(Iterable<String> sourceIds) async {
    _reels.clear();
    for (final id in sourceIds) {
      final json = await _store.read('reels/$id.json');
      for (final e in (json is List ? json : const [])) {
        final reel = Reel.fromJson(jMap(e));
        _reels[reel.id] = reel;
      }
    }
    notifyListeners();
  }

  void addAll(List<Reel> reels) {
    if (reels.isEmpty) return;
    final touched = <String>{};
    for (final r in reels) {
      _reels[r.id] = r;
      touched.add(r.sourceId);
    }
    touched.forEach(_scheduleSave);
    notifyListeners();
  }

  Future<void> removeSource(String sourceId) async {
    _reels.removeWhere((_, r) => r.sourceId == sourceId);
    await _store.delete('reels/$sourceId.json');
    notifyListeners();
  }

  Future<void> clear(Iterable<String> sourceIds) async {
    _reels.clear();
    for (final id in sourceIds) {
      await _store.delete('reels/$id.json');
    }
    notifyListeners();
  }

  void _scheduleSave(String sourceId) =>
      _store.scheduleWrite('reels/$sourceId.json', () => forSource(sourceId).map((r) => r.toJson()).toList());
}

/// Per-chunk progress, per-reel spaced repetition state and global stats.
class ProgressRepository extends ChangeNotifier {
  ProgressRepository(this._store);

  final JsonStore _store;
  final Map<String, ChunkProgress> _chunks = {};
  final Map<String, ReelState> _reels = {};
  StudyStats stats = StudyStats();

  ChunkProgress chunk(String chunkId, String sourceId) =>
      _chunks.putIfAbsent(chunkId, () => ChunkProgress(chunkId: chunkId, sourceId: sourceId));

  ChunkProgress? peekChunk(String chunkId) => _chunks[chunkId];

  ReelState reel(String reelId) => _reels.putIfAbsent(reelId, () => ReelState(reelId: reelId));

  ReelState? peekReel(String reelId) => _reels[reelId];

  Iterable<ReelState> get reelStates => _reels.values;
  Iterable<ChunkProgress> get chunkProgress => _chunks.values;

  Future<void> load() async {
    final json = jMap(await _store.read('progress.json'));
    _chunks
      ..clear()
      ..addEntries(
        jMap(json['chunks']).values.map((e) {
          final cp = ChunkProgress.fromJson(jMap(e));
          return MapEntry(cp.chunkId, cp);
        }),
      );
    _reels
      ..clear()
      ..addEntries(
        jMap(json['reels']).values.map((e) {
          final rs = ReelState.fromJson(jMap(e));
          return MapEntry(rs.reelId, rs);
        }),
      );
    stats = StudyStats.fromJson(jMap(json['stats']));
    notifyListeners();
  }

  /// Call after mutating any progress object.
  void changed() {
    _store.scheduleWrite('progress.json', _toJson);
    notifyListeners();
  }

  Map<String, dynamic> _toJson() => {
    'chunks': _chunks.map((k, v) => MapEntry(k, v.toJson())),
    'reels': _reels.map((k, v) => MapEntry(k, v.toJson())),
    'stats': stats.toJson(),
  };

  void removeSource(String sourceId, Iterable<String> reelIds) {
    _chunks.removeWhere((_, c) => c.sourceId == sourceId);
    for (final id in reelIds) {
      _reels.remove(id);
    }
    changed();
  }

  void resetAll() {
    _chunks.clear();
    _reels.clear();
    stats = StudyStats();
    changed();
  }
}

/// Pen annotations per reel.
class AnnotationRepository extends ChangeNotifier {
  AnnotationRepository(this._store);

  final JsonStore _store;
  final Map<String, List<PenStroke>> _strokes = {};

  List<PenStroke> strokesFor(String key) => _strokes[key] ?? const [];

  Future<void> load() async {
    final json = jMap(await _store.read('annotations.json'));
    _strokes
      ..clear()
      ..addAll(
        json.map((k, v) => MapEntry(k, (v is List ? v : const []).map((e) => PenStroke.fromJson(jMap(e))).toList())),
      );
  }

  void setStrokes(String key, List<PenStroke> strokes) {
    if (strokes.isEmpty) {
      _strokes.remove(key);
    } else {
      _strokes[key] = List.of(strokes);
    }
    _store.scheduleWrite(
      'annotations.json',
      () => _strokes.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
    );
    notifyListeners();
  }

  void removeWhere(bool Function(String key) test) {
    _strokes.removeWhere((k, _) => test(k));
    _store.scheduleWrite(
      'annotations.json',
      () => _strokes.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
    );
  }
}
