import 'dart:io';

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
      if (s.documents.isEmpty && _chunks[s.id]!.isNotEmpty) {
        // Single-document source from before collections existed.
        s.documents.add(
          SourceDocument(id: 'd0', title: s.title, format: s.format, fileName: s.originalFileName, addedAt: s.addedAt),
        );
      }
      _updateCounts(s);
    }
    notifyListeners();
  }

  void _updateCounts(StudySource s) {
    final chunks = this.chunks(s.id);
    s.chunkCount = chunks.length;
    s.charCount = chunks.fold(0, (sum, c) => sum + c.text.length);
    for (final d in s.documents) {
      final own = chunks.where((c) => c.documentId == d.id);
      d.chunkCount = own.length;
      d.charCount = own.fold(0, (sum, c) => sum + c.text.length);
    }
  }

  Future<void> addSource(StudySource source, List<SourceChunk> chunks) async {
    _sources.insert(0, source);
    _chunks[source.id] = chunks;
    _updateCounts(source);
    await _saveChunks(source.id);
    await _saveIndex();
    notifyListeners();
  }

  /// The document a section belongs to.
  SourceDocument? documentOf(SourceChunk chunk) => source(chunk.sourceId)?.document(chunk.documentId);

  /// Appends a document (with its sections) to a source.
  Future<void> addDocument(String sourceId, SourceDocument document, List<SourceChunk> chunks) async {
    final s = source(sourceId);
    if (s == null) return;
    s.documents.add(document);
    _chunks[sourceId] = [...this.chunks(sourceId), ...chunks];
    _reindex(s);
    await _saveChunks(sourceId);
    await _saveIndex();
    notifyListeners();
  }

  /// Removes a document and returns its sections (for cleaning up reels/progress/figures).
  Future<List<SourceChunk>> removeDocument(String sourceId, String documentId) async {
    final s = source(sourceId);
    if (s == null) return const [];
    final removed = chunks(sourceId).where((c) => c.documentId == documentId).toList();
    s.documents.removeWhere((d) => d.id == documentId);
    _chunks[sourceId] = chunks(sourceId).where((c) => c.documentId != documentId).toList();
    for (final img in removed.expand((c) => c.images)) {
      final file = _store.file('images/$sourceId/${img.file}');
      if (await file.exists()) await file.delete();
    }
    _reindex(s);
    await _saveChunks(sourceId);
    await _saveIndex();
    notifyListeners();
    return removed;
  }

  /// Moves a document up (-1) or down (+1) in the reading order.
  Future<void> moveDocument(String sourceId, String documentId, int delta) async {
    final s = source(sourceId);
    if (s == null) return;
    final i = s.documents.indexWhere((d) => d.id == documentId);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= s.documents.length) return;
    final d = s.documents.removeAt(i);
    s.documents.insert(j, d);
    _reindex(s);
    await _saveChunks(sourceId);
    await _saveIndex();
    notifyListeners();
  }

  /// Orders sections by document order and renumbers them (chunk ids stay stable).
  void _reindex(StudySource s) {
    final order = {for (var i = 0; i < s.documents.length; i++) s.documents[i].id: i};
    final sorted = List.of(chunks(s.id))
      ..sort((a, b) {
        final c = (order[a.documentId] ?? 999).compareTo(order[b.documentId] ?? 999);
        return c != 0 ? c : a.index.compareTo(b.index);
      });
    _chunks[s.id] = [for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(index: i)];
    _updateCounts(s);
  }

  Future<void> _saveChunks(String sourceId) =>
      _store.write('chunks/$sourceId.json', chunks(sourceId).map((c) => c.toJson()).toList());

  Future<void> updateSource(StudySource source) async {
    await _saveIndex();
    notifyListeners();
  }

  /// Saves figure files for a source (`images/<sourceId>/<file>`).
  Future<void> saveImages(String sourceId, Map<String, List<int>> files) async {
    for (final e in files.entries) {
      await _store.writeBytes('images/$sourceId/${e.key}', e.value);
    }
  }

  /// File of a figure referenced by reels (`img3`), or null if unknown.
  File? imageFile(String sourceId, String imageId) {
    for (final c in chunks(sourceId)) {
      for (final img in c.images) {
        if (img.id == imageId) return _store.file('images/$sourceId/${img.file}');
      }
    }
    return null;
  }

  Future<void> removeSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    _chunks.remove(id);
    await _store.deleteDirectory('images/$id');
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

  /// Removes reels by id (e.g. retired or belonging to a removed document).
  void removeIds(Set<String> ids) {
    final touched = <String>{};
    _reels.removeWhere((id, r) {
      final remove = ids.contains(id);
      if (remove) touched.add(r.sourceId);
      return remove;
    });
    touched.forEach(_scheduleSave);
    if (touched.isNotEmpty) notifyListeners();
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

  void removeReelStates(Set<String> reelIds) {
    for (final id in reelIds) {
      _reels.remove(id);
    }
  }

  void removeChunks(Set<String> chunkIds, Iterable<String> reelIds) {
    _chunks.removeWhere((id, _) => chunkIds.contains(id));
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
