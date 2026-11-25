import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models/chunk.dart';
import '../../core/models/reel.dart';
import '../../core/models/source.dart';
import '../../core/storage/repositories.dart';
import '../../core/storage/settings_repository.dart';
import '../generation/generation_job.dart';
import '../generation/generation_service.dart';
import '../reels/reel_types.dart';
import '../study/progress_tracker.dart';
import '../study/study_mode.dart';

class FeedItem {
  FeedItem(this.reel, {this.isReview = false});
  final Reel reel;
  final bool isReview;
}

/// Composes the endless reel feed.
///
/// For every batch it (1) mixes in due spaced-repetition reviews, (2) picks a
/// source according to the configured feed shares, (3) asks that source's
/// [StudyMode] which section comes next, (4) re-uses unseen cached reels for
/// that section and (5) generates new ones with the active generator.
class FeedEngine extends ChangeNotifier {
  FeedEngine({
    required this.library,
    required this.reels,
    required this.progress,
    required this.settings,
    required this.generation,
    required this.modes,
    required this.tracker,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  final LibraryRepository library;
  final ReelRepository reels;
  final ProgressRepository progress;
  final SettingsRepository settings;
  final GenerationService generation;
  final StudyModes modes;
  final ProgressTracker tracker;
  final Random _random;
  final DateTime Function() _clock;

  final List<FeedItem> items = [];
  int currentIndex = 0;
  bool isGenerating = false;
  String? generatingLabel;
  String? lastError;

  /// Set when the feed has nothing more to show (no sources / all done).
  String? emptyReason;

  /// Temporary focus on one section ("Study this section").
  String? focusChunkId;

  DateTime? _pausedUntil;
  Future<void>? _running;

  DateTime get now => _clock();

  FeedItem? get current => currentIndex < items.length ? items[currentIndex] : null;
  int get remainingAhead => items.length - currentIndex - 1;

  List<StudySource> get activeSources {
    final focus = settings.settings.feed.focusSourceId;
    final focusChunkSource = focusChunkId?.split(':').first;
    return library.sources.where((s) {
      if (s.chunkCount == 0) return false;
      if (focusChunkSource != null) return s.id == focusChunkSource;
      if (focus != null) return s.id == focus;
      return s.study.includeInFeed;
    }).toList();
  }

  /// Normalised feed share per source (0..1).
  Map<String, double> sourceShares() {
    final sources = library.sources.where((s) => s.study.includeInFeed && s.chunkCount > 0).toList();
    final total = sources.fold<double>(0, (a, s) => a + s.study.feedWeight);
    return {for (final s in sources) s.id: total <= 0 ? 0 : s.study.feedWeight / total};
  }

  StudyContext contextFor(StudySource source) => StudyContext(
    source: source,
    chunks: library.chunks(source.id),
    progress: progress,
    reels: reels,
    now: now,
    random: _random,
  );

  /// Called by the UI when a reel becomes visible.
  void onPageChanged(int index) {
    if (index < 0 || index >= items.length) {
      currentIndex = index.clamp(0, items.length);
      notifyListeners();
      ensureBuffer();
      return;
    }
    currentIndex = index;
    // Count each reel once per session, even when scrolling back and forth.
    if (_viewed.add(items[index].reel.id)) tracker.recordView(items[index].reel, now);
    notifyListeners();
    ensureBuffer();
  }

  final Set<String> _viewed = {};

  /// Fill the queue in the background when it runs low.
  Future<void> ensureBuffer({bool force = false}) {
    if (_running != null) return _running!;
    final threshold = settings.settings.feed.prefetchThreshold;
    if (!force && remainingAhead >= threshold) return Future.value();
    if (!force && _pausedUntil != null && now.isBefore(_pausedUntil!)) return Future.value();
    final future = _fill().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<void> retry() {
    _pausedUntil = null;
    lastError = null;
    notifyListeners();
    return ensureBuffer(force: true);
  }

  /// Drops upcoming (unseen) items and rebuilds the queue, e.g. after settings changed.
  Future<void> refresh() async {
    if (_running != null) await _running;
    if (items.length > currentIndex + 1) items.removeRange(currentIndex + 1, items.length);
    emptyReason = null;
    _pausedUntil = null;
    notifyListeners();
    await ensureBuffer(force: true);
  }

  Future<void> setFocusChunk(String? chunkId) async {
    focusChunkId = chunkId;
    await refresh();
  }

  Future<void> _fill() async {
    final sources = activeSources;
    if (sources.isEmpty) {
      emptyReason = library.sources.isEmpty ? 'no_sources' : 'no_active_sources';
      notifyListeners();
      return;
    }
    emptyReason = null;
    final feed = settings.settings.feed;
    final batch = settings.settings.generation.reelsPerRequest;
    // Upcoming items must not repeat; anything already in this session's feed
    // is only re-shown as a (due) review.
    final queued = items.skip(currentIndex).map((i) => i.reel.id).toSet();
    final inFeed = items.map((i) => i.reel.id).toSet();
    final sourceIds = sources.map((s) => s.id).toSet();

    // 1) Spaced-repetition reviews.
    final avgBoost = sources.fold<double>(0, (a, s) => a + modes.byId(s.study.modeId).reviewBoost) / sources.length;
    final reviewSlots = focusChunkId != null ? 0 : (batch * (feed.reviewShare * avgBoost).clamp(0.0, 0.8)).round();
    final due =
        reels.all
            .where((r) => sourceIds.contains(r.sourceId) && !queued.contains(r.id))
            .where((r) => progress.peekReel(r.id)?.isDue(now) ?? false)
            .toList()
          ..sort((a, b) => progress.peekReel(a.id)!.due!.compareTo(progress.peekReel(b.id)!.due!));
    final reviews = due.take(reviewSlots).map((r) => FeedItem(r, isReview: true)).toList();

    // 2) New content from one source/section.
    final fresh = <FeedItem>[];
    final pick = _pickSection(sources);
    if (pick != null) {
      final (source, chunk, mode) = pick;
      final cached = reels
          .forChunk(chunk.id)
          .where((r) => !inFeed.contains(r.id) && (progress.peekReel(r.id)?.views ?? 0) == 0)
          .toList();
      fresh.addAll(cached.take(batch).map(FeedItem.new));
      final missing = batch - fresh.length;
      if (missing > 0 && (fresh.length < (batch / 2).ceil())) {
        final generated = await _generate(source, chunk, mode, missing);
        fresh.addAll(generated.map(FeedItem.new));
      }
      _orderForMode(fresh, mode);
    }

    if (fresh.isEmpty && reviews.isEmpty) {
      // Nothing new: re-surface the least recently seen reels so the feed never dead-ends.
      final old = reels.all.where((r) => sourceIds.contains(r.sourceId) && !queued.contains(r.id)).toList()
        ..sort(
          (a, b) => (progress.peekReel(a.id)?.lastViewed ?? DateTime(2000)).compareTo(
            progress.peekReel(b.id)?.lastViewed ?? DateTime(2000),
          ),
        );
      reviews.addAll(old.take(batch).map((r) => FeedItem(r, isReview: true)));
    }
    if (fresh.isEmpty && reviews.isEmpty) {
      if (lastError == null) emptyReason = 'nothing_to_show';
      notifyListeners();
      return;
    }

    // Interleave reviews between fresh reels.
    final merged = <FeedItem>[];
    final gap = reviews.isEmpty ? 0 : max(1, (fresh.length / (reviews.length + 1)).ceil());
    var r = 0;
    for (var i = 0; i < fresh.length; i++) {
      merged.add(fresh[i]);
      if (gap > 0 && (i + 1) % gap == 0 && r < reviews.length) merged.add(reviews[r++]);
    }
    merged.addAll(reviews.skip(r));
    items.addAll(merged);
    // The page that is already on screen never fires a page change: count it now.
    if (currentIndex < items.length && _viewed.add(items[currentIndex].reel.id)) {
      tracker.recordView(items[currentIndex].reel, now);
    }
    notifyListeners();
  }

  (StudySource, SourceChunk, StudyMode)? _pickSection(List<StudySource> sources) {
    if (focusChunkId != null) {
      final chunk = library.chunk(focusChunkId!);
      final source = chunk == null ? null : library.source(chunk.sourceId);
      if (chunk != null && source != null) return (source, chunk, modes.byId(source.study.modeId));
    }
    final candidates = List.of(sources);
    while (candidates.isNotEmpty) {
      final source = _weightedPick(candidates);
      final mode = modes.byId(source.study.modeId);
      final chunk = mode.nextChunk(contextFor(source));
      if (chunk != null) return (source, chunk, mode);
      candidates.remove(source);
    }
    return null;
  }

  StudySource _weightedPick(List<StudySource> sources) {
    final total = sources.fold<double>(0, (a, s) => a + max(0.01, s.study.feedWeight));
    var r = _random.nextDouble() * total;
    for (final s in sources) {
      r -= max(0.01, s.study.feedWeight);
      if (r <= 0) return s;
    }
    return sources.last;
  }

  /// Picks [count] reel types from the weighted mix.
  List<String> sampleTypes(StudyMode mode, String chunkId, int count) {
    final feed = settings.settings.feed;
    final base = feed.useModeReelMix || feed.reelTypeWeights.values.every((w) => w <= 0)
        ? mode.defaultReelMix
        : feed.reelTypeWeights;
    final mix = Map.of(mode.mixFor(progress.peekChunk(chunkId), base))
      ..removeWhere((k, v) => v <= 0 || ReelTypes.byId(k) == null);
    if (mix.isEmpty) mix['explainer'] = 1;
    final total = mix.values.fold<double>(0, (a, b) => a + b);
    final result = <String>[];
    for (var i = 0; i < count; i++) {
      var r = _random.nextDouble() * total;
      for (final e in mix.entries) {
        r -= e.value;
        if (r <= 0) {
          result.add(e.key);
          break;
        }
      }
      if (result.length <= i) result.add(mix.keys.first);
    }
    // Avoid batches with no teaching at all on first contact in teach-first modes.
    final p = progress.peekChunk(chunkId);
    if (mode.teachFirst && (p == null || p.reelsSeen == 0) && !result.any((t) => ReelTypes.byId(t)!.isTeaching)) {
      result[0] = 'explainer';
    }
    return result;
  }

  void _orderForMode(List<FeedItem> list, StudyMode mode) {
    if (!mode.teachFirst) return;
    int rank(FeedItem i) => (ReelTypes.byId(i.reel.type)?.isTeaching ?? false) ? 0 : 1;
    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final c = rank(a.value).compareTo(rank(b.value));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    list
      ..clear()
      ..addAll(indexed.map((e) => e.value));
  }

  Future<List<Reel>> _generate(
    StudySource source,
    SourceChunk chunk,
    StudyMode mode,
    int count, {
    String? focus,
    String? parentReelId,
  }) async {
    isGenerating = true;
    generatingLabel = chunk.title;
    lastError = null;
    notifyListeners();
    final chunks = library.chunks(source.id);
    final job = GenerationJob(
      source: source,
      chunk: chunk,
      chunkCount: chunks.length,
      reelTypes: focus != null ? _followUpTypes(mode) : sampleTypes(mode, chunk.id, count),
      mode: mode,
      settings: settings.settings.generation,
      progress: progress.peekChunk(chunk.id),
      previousChunkTitle: chunk.index > 0 && chunk.index - 1 < chunks.length ? chunks[chunk.index - 1].title : null,
      existingSummaries: reels.forChunk(chunk.id).map((r) => r.summary).toList(),
      focus: focus,
      parentReelId: parentReelId,
    );
    try {
      List<Reel> result;
      try {
        final generator = await generation.current();
        result = await generator.generate(job);
      } catch (e) {
        lastError = e.toString();
        if (!settings.settings.generation.fallbackToOffline) rethrow;
        result = await generation.offline.generate(job);
      }
      // Drop reels that repeat existing content for this section.
      final existing = reels.forChunk(chunk.id).map((r) => '${r.type}|${r.summary}').toSet();
      result = result.where((r) => existing.add('${r.type}|${r.summary}')).toList();
      reels.addAll(result);
      return result;
    } catch (e) {
      lastError = e.toString();
      _pausedUntil = now.add(const Duration(seconds: 30));
      return const [];
    } finally {
      isGenerating = false;
      generatingLabel = null;
      notifyListeners();
    }
  }

  List<String> _followUpTypes(StudyMode mode) => ['explainer', 'explainer', mode.id == 'rote' ? 'flashcard' : 'quiz'];

  /// "Explain more": generates deeper follow-up reels and inserts them right after the current one.
  Future<void> explainMore(Reel reel) async {
    final chunk = library.chunk(reel.chunkId);
    final source = library.source(reel.sourceId);
    if (chunk == null || source == null) return;
    final mode = modes.byId(source.study.modeId);
    final generated = await _generate(source, chunk, mode, 3, focus: reel.summary, parentReelId: reel.id);
    final at = (items.indexWhere((i) => i.reel.id == reel.id) + 1).clamp(0, items.length);
    items.insertAll(at, generated.map(FeedItem.new));
    notifyListeners();
  }

  /// Removes everything belonging to a deleted source from the queue.
  void removeSource(String sourceId) {
    final before = items.take(currentIndex + 1).where((i) => i.reel.sourceId == sourceId).length;
    items.removeWhere((i) => i.reel.sourceId == sourceId);
    currentIndex = (currentIndex - before).clamp(0, max(0, items.length - 1));
    if (focusChunkId?.startsWith('$sourceId:') ?? false) focusChunkId = null;
    notifyListeners();
  }
}
