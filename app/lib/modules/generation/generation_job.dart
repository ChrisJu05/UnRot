import '../../core/models/chunk.dart';
import '../../core/models/progress.dart';
import '../../core/models/reel.dart';
import '../../core/models/settings.dart';
import '../../core/models/source.dart';
import '../study/study_mode.dart';

/// Everything a generator needs to produce reels for one section.
class GenerationJob {
  GenerationJob({
    required this.source,
    required this.chunk,
    required this.chunkCount,
    required this.reelTypes,
    required this.mode,
    required this.settings,
    this.progress,
    this.previousChunkTitle,
    this.existingSummaries = const [],
    this.focus,
    this.parentReelId,
  });

  final StudySource source;
  final SourceChunk chunk;
  final int chunkCount;

  /// Requested reel types, in feed order.
  final List<String> reelTypes;
  final StudyMode mode;
  final GenerationSettings settings;
  final ChunkProgress? progress;
  final String? previousChunkTitle;

  /// Summaries of reels that already exist for this section (avoid repeats).
  final List<String> existingSummaries;

  /// "Explain more" focus: the reel content the learner wants to go deeper on.
  final String? focus;
  final String? parentReelId;

  /// Effective reel language: `source` or a language name.
  String get language => effectiveLanguage(source, settings);

  /// Per-source language wins over the app-wide default.
  static String effectiveLanguage(StudySource source, GenerationSettings settings) {
    final perSource = source.study.reelLanguage;
    return perSource.isEmpty || perSource == 'default' ? settings.language : perSource;
  }

  /// 1 = easy, 2 = medium, 3 = hard.
  int get difficulty {
    switch (settings.difficulty) {
      case 'easy':
        return 1;
      case 'medium':
        return 2;
      case 'hard':
        return 3;
    }
    final p = progress;
    var level = 2;
    if (p == null || p.reelsSeen < 3) {
      level = 1;
    } else if (p.mastery >= 0.75) {
      level = 3;
    } else if (p.mastery < 0.35) {
      level = 1;
    }
    return (level + (p?.difficultyBias ?? 0)).clamp(1, 3);
  }
}

/// Produces reels for a [GenerationJob].
abstract class ReelGenerator {
  /// e.g. `anthropic:claude-opus-5-5` or `offline`.
  String get id;

  Future<List<Reel>> generate(GenerationJob job);
}
