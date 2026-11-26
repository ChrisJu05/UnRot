import 'dart:math';

import '../../../core/models/chunk.dart';
import '../../../core/models/progress.dart';
import '../study_mode.dart';

List<StudyMode> builtinStudyModes() => const [LinearMode(), ExamPrepMode(), RoteMode(), ExploreMode()];

/// Go through the material in order, section by section, like a course.
class LinearMode extends StudyMode {
  const LinearMode();

  @override
  String get id => 'linear';
  @override
  String get name => 'Linear course';
  @override
  String get tagline => 'Learn it step by step, in order';
  @override
  String get description =>
      'Works through the material from start to finish. Each section is explained first, then checked with '
      'questions; you move on once you have seen enough and answer most questions correctly.';
  @override
  Map<String, double> get defaultReelMix => const {
    'explainer': 3,
    'key_points': 1.5,
    'quiz': 2,
    'true_false': 1,
    'cloze': 1,
    'flashcard': 0.5,
    'mnemonic': 0.5,
    'write_recall': 0.5,
    'visual': 1.5,
  };
  @override
  String get promptGuidance =>
      'The learner is working through the material in order like a course. Build understanding first: '
      'explain the ideas of this section clearly, connect them to what came before, then check understanding.';

  static const minReels = 4;
  static const maxReels = 14;

  @override
  bool isComplete(ChunkProgress? p) =>
      p != null && (p.reelsSeen >= maxReels || (p.reelsSeen >= minReels && p.mastery >= 0.5));

  @override
  SourceChunk? nextChunk(StudyContext ctx) {
    for (final c in ctx.chunks) {
      if (!isComplete(ctx.progressOf(c))) return c;
    }
    return null;
  }

  @override
  Map<String, double> mixFor(ChunkProgress? progress, Map<String, double> base) {
    if (progress == null || progress.reelsSeen < 2) {
      return {'explainer': 4, 'key_points': 1.5, 'visual': 1.5, 'quiz': 1, 'true_false': 0.5, 'mnemonic': 0.5};
    }
    return base;
  }
}

/// Cover everything before the exam date, prioritising weak spots.
class ExamPrepMode extends StudyMode {
  const ExamPrepMode();

  @override
  String get id => 'exam';
  @override
  String get name => 'Exam prep';
  @override
  String get tagline => 'Cover everything, drill weak spots';
  @override
  String get description =>
      'Paces the material towards your exam date. Focuses on exam-style questions, repeats sections you '
      'struggle with and mixes in more reviews as the exam gets closer.';
  @override
  Map<String, double> get defaultReelMix => const {
    'quiz': 4,
    'true_false': 1.5,
    'cloze': 1.5,
    'write_recall': 1.5,
    'flashcard': 1,
    'explainer': 1,
    'key_points': 1,
    'visual': 1,
  };
  @override
  String get promptGuidance =>
      'The learner is preparing for an exam. Prefer exam-style questions that test understanding and '
      'application, highlight typical pitfalls and things examiners like to ask. Keep explanations brief.';
  @override
  double get reviewBoost => 1.3;

  @override
  bool isComplete(ChunkProgress? p) => p != null && p.reelsSeen >= 3 && p.mastery >= 0.6;

  /// Days until the exam (null without date).
  static int? daysLeft(StudyContext ctx) {
    final date = ctx.source.study.examDate;
    if (date == null) return null;
    final today = DateTime(ctx.now.year, ctx.now.month, ctx.now.day);
    return DateTime(date.year, date.month, date.day).difference(today).inDays;
  }

  /// Sections per day needed to cover the remaining material in time.
  static double? requiredPace(StudyContext ctx, StudyMode mode) {
    final days = daysLeft(ctx);
    if (days == null) return null;
    final remaining = ctx.chunks.where((c) => !mode.isComplete(ctx.progressOf(c))).length;
    return remaining / max(1, days);
  }

  @override
  SourceChunk? nextChunk(StudyContext ctx) {
    final uncovered = ctx.chunks.where((c) => !isComplete(ctx.progressOf(c))).toList();
    final weak = ctx.chunks.where((c) {
      final p = ctx.progressOf(c);
      return p != null && p.reelsSeen > 0 && p.mastery < 0.6;
    }).toList()..sort((a, b) => ctx.progressOf(a)!.mastery.compareTo(ctx.progressOf(b)!.mastery));
    final days = daysLeft(ctx);
    double pWeak;
    if (uncovered.isEmpty) {
      pWeak = 1;
    } else if (days == null) {
      pWeak = 0.3;
    } else if (days <= 1) {
      pWeak = 0.8;
    } else {
      pWeak = (0.25 + 0.5 * (1 - min(days, 30) / 30)).clamp(0.25, 0.75);
    }
    if (weak.isNotEmpty && ctx.random.nextDouble() < pWeak) {
      return weak[ctx.random.nextInt(min(3, weak.length))];
    }
    final unseenOrLearning = uncovered.where((c) => !weak.contains(c)).toList();
    if (unseenOrLearning.isNotEmpty) return unseenOrLearning.first;
    if (uncovered.isNotEmpty) return uncovered.first;
    // Everything covered: keep drilling the least mastered sections.
    final sorted = List.of(ctx.chunks)
      ..sort((a, b) => (ctx.progressOf(a)?.mastery ?? 0).compareTo(ctx.progressOf(b)?.mastery ?? 0));
    return sorted.firstOrNull;
  }
}

/// Memorise everything (definitions, vocabulary, formulas) with spaced repetition.
class RoteMode extends StudyMode {
  const RoteMode();

  @override
  String get id => 'rote';
  @override
  String get name => 'Memorise (rote)';
  @override
  String get tagline => 'Learn every detail by heart';
  @override
  String get description =>
      'Turns the material into flashcards, gap texts and write-from-memory tasks and schedules them with '
      'spaced repetition until you know everything by heart. New sections are introduced only when your '
      'review pile is under control.';
  @override
  Map<String, double> get defaultReelMix => const {
    'flashcard': 4,
    'cloze': 3,
    'write_recall': 2,
    'mnemonic': 1.5,
    'quiz': 1,
    'visual': 0.3,
  };
  @override
  String get promptGuidance =>
      'The learner wants to memorise this material completely and precisely. Turn EVERY fact, definition, '
      'term, number, list and formula into atomic recall items; keep the exact wording where precision matters.';
  @override
  bool get teachFirst => false;
  @override
  double get reviewBoost => 1.8;

  static const maxDueBeforeNew = 25;

  @override
  bool isComplete(ChunkProgress? p) => p != null && p.reelsSeen >= 5 && p.mastery >= 0.85;

  @override
  SourceChunk? nextChunk(StudyContext ctx) {
    if (ctx.dueReviewsInSource() > maxDueBeforeNew) return null;
    for (final c in ctx.chunks) {
      if (!isComplete(ctx.progressOf(c))) return c;
    }
    return null;
  }
}

/// Discover the material in random order, TikTok-style.
class ExploreMode extends StudyMode {
  const ExploreMode();

  @override
  String get id => 'explore';
  @override
  String get name => 'Explore / shuffle';
  @override
  String get tagline => 'Random bites from everywhere';
  @override
  String get description =>
      'Jumps around the material in random order, favouring sections you have seen least. Great for '
      'casual scrolling and getting an overview.';
  @override
  Map<String, double> get defaultReelMix => const {
    'explainer': 3,
    'key_points': 1.5,
    'quiz': 2,
    'true_false': 2,
    'mnemonic': 1,
    'visual': 2,
  };
  @override
  String get promptGuidance =>
      'The learner is casually exploring. Make reels intriguing and self-contained: surprising facts, '
      'vivid examples, "did you know" hooks — still strictly based on the source.';
  @override
  double get reviewBoost => 0.6;

  @override
  bool isComplete(ChunkProgress? p) => p != null && p.reelsSeen >= 3;

  @override
  SourceChunk? nextChunk(StudyContext ctx) {
    if (ctx.chunks.isEmpty) return null;
    final weights = ctx.chunks.map((c) => 1 / (1 + (ctx.progressOf(c)?.reelsSeen ?? 0))).toList();
    final total = weights.fold<double>(0, (a, b) => a + b);
    var r = ctx.random.nextDouble() * total;
    for (var i = 0; i < ctx.chunks.length; i++) {
      r -= weights[i];
      if (r <= 0) return ctx.chunks[i];
    }
    return ctx.chunks.last;
  }
}
