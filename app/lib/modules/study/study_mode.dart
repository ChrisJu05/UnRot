import 'dart:math';

import '../../core/models/chunk.dart';
import '../../core/models/progress.dart';
import '../../core/models/source.dart';
import '../../core/storage/repositories.dart';

/// Everything a [StudyMode] may look at to decide what comes next.
class StudyContext {
  StudyContext({
    required this.source,
    required this.chunks,
    required this.progress,
    required this.reels,
    required this.now,
    Random? random,
  }) : random = random ?? Random();

  final StudySource source;
  final List<SourceChunk> chunks;
  final ProgressRepository progress;
  final ReelRepository reels;
  final DateTime now;
  final Random random;

  ChunkProgress? progressOf(SourceChunk chunk) => progress.peekChunk(chunk.id);

  int dueReviewsInSource() =>
      reels.forSource(source.id).where((r) => progress.peekReel(r.id)?.isDue(now) ?? false).length;
}

/// A strategy for working through a source. Modes are pluggable: implement
/// this class and register it in [StudyModes.all].
abstract class StudyMode {
  const StudyMode();

  String get id;
  String get name;
  String get tagline;
  String get description;

  /// Default relative weights of reel types (see `ReelTypes`).
  Map<String, double> get defaultReelMix;

  /// Explains the learning goal to the AI.
  String get promptGuidance;

  /// Show teaching reels (explainers) before questions for a section.
  bool get teachFirst => true;

  /// Multiplier for how many spaced-repetition reviews are mixed in.
  double get reviewBoost => 1.0;

  /// The section to produce new reels for next, or null if nothing new is needed
  /// right now (the feed then falls back to reviews).
  SourceChunk? nextChunk(StudyContext ctx);

  /// Whether the learner is done with [chunk] for the purpose of moving on.
  bool isComplete(ChunkProgress? progress);

  /// Reel mix for a specific chunk (e.g. more explainers on first contact).
  Map<String, double> mixFor(ChunkProgress? progress, Map<String, double> base) => base;

  /// Fraction 0..1 of the source that is complete in this mode.
  double completion(StudyContext ctx) {
    if (ctx.chunks.isEmpty) return 0;
    return ctx.chunks.where((c) => isComplete(ctx.progressOf(c))).length / ctx.chunks.length;
  }
}

/// Registry of study modes.
class StudyModes {
  StudyModes(this.all);

  final List<StudyMode> all;

  StudyMode byId(String id) => all.firstWhere((m) => m.id == id, orElse: () => all.first);
}
