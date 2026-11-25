import '../../core/models/progress.dart';
import '../../core/models/reel.dart';
import '../../core/storage/repositories.dart';
import '../reels/reel_types.dart';

enum RecallRating { again, hard, good, easy }

enum ReelFeedback { gotIt, confusing, tooEasy }

/// SM-2 style spaced repetition scheduling.
class SpacedRepetition {
  static void schedule(ReelState s, RecallRating rating, DateTime now) {
    switch (rating) {
      case RecallRating.again:
        s.repetitions = 0;
        s.lapses++;
        s.ease = (s.ease - 0.2).clamp(1.3, 3.0);
        s.intervalDays = 0;
        s.due = now.add(const Duration(minutes: 10));
        return;
      case RecallRating.hard:
        s.repetitions++;
        s.ease = (s.ease - 0.15).clamp(1.3, 3.0);
        s.intervalDays = s.repetitions == 1 ? 1 : (s.intervalDays * 1.2).clamp(1, 3650);
      case RecallRating.good:
        s.repetitions++;
        s.intervalDays = switch (s.repetitions) {
          1 => 1,
          2 => 3,
          _ => (s.intervalDays * s.ease).clamp(1, 3650),
        };
      case RecallRating.easy:
        s.repetitions++;
        s.ease = (s.ease + 0.15).clamp(1.3, 3.0);
        s.intervalDays = switch (s.repetitions) {
          1 => 3,
          2 => 6,
          _ => (s.intervalDays * s.ease * 1.3).clamp(1, 3650),
        };
    }
    s.due = now.add(Duration(minutes: (s.intervalDays * 24 * 60).round()));
  }
}

/// Turns learner interactions into progress, mastery and review schedules.
class ProgressTracker {
  ProgressTracker(this.progress);

  final ProgressRepository progress;

  void recordView(Reel reel, DateTime now) {
    final rs = progress.reel(reel.id);
    final cp = progress.chunk(reel.chunkId, reel.sourceId);
    final firstView = rs.views == 0;
    rs.views++;
    rs.lastViewed = now;
    cp.lastSeen = now;
    cp.firstSeen ??= now;
    if (firstView) {
      cp.reelsSeen++;
      final spec = ReelTypes.byId(reel.type);
      if (spec != null && !spec.isRecall) cp.mastery += 0.06 * (1 - cp.mastery);
    }
    final stats = progress.stats;
    stats.totalReels++;
    final key = StudyStats.dayKey(now);
    stats.reelsPerDay[key] = (stats.reelsPerDay[key] ?? 0) + 1;
    progress.changed();
  }

  void recordAnswer(Reel reel, bool correct, DateTime now) {
    final rs = progress.reel(reel.id);
    final cp = progress.chunk(reel.chunkId, reel.sourceId);
    rs.lastCorrect = correct;
    if (correct) {
      cp.correct++;
      progress.stats.totalCorrect++;
    } else {
      cp.incorrect++;
      cp.rememberMissed(reel.summary);
    }
    progress.stats.totalAnswered++;
    cp.mastery += 0.3 * ((correct ? 1 : 0) - cp.mastery);
    SpacedRepetition.schedule(rs, correct ? RecallRating.good : RecallRating.again, now);
    progress.changed();
  }

  void recordRating(Reel reel, RecallRating rating, DateTime now) {
    final rs = progress.reel(reel.id);
    final cp = progress.chunk(reel.chunkId, reel.sourceId);
    final score = const [0.0, 0.5, 0.85, 1.0][rating.index];
    final correct = rating.index >= RecallRating.good.index;
    rs.lastCorrect = correct;
    if (correct) {
      cp.correct++;
      progress.stats.totalCorrect++;
    } else {
      cp.incorrect++;
      if (rating == RecallRating.again) cp.rememberMissed(reel.summary);
    }
    progress.stats.totalAnswered++;
    cp.mastery += 0.3 * (score - cp.mastery);
    SpacedRepetition.schedule(rs, rating, now);
    progress.changed();
  }

  void recordFeedback(Reel reel, ReelFeedback feedback) {
    final cp = progress.chunk(reel.chunkId, reel.sourceId);
    switch (feedback) {
      case ReelFeedback.confusing:
        cp.confusedVotes++;
        cp.difficultyBias = (cp.difficultyBias - 1).clamp(-2, 2);
        cp.rememberConfusing(reel.summary);
        cp.mastery -= 0.1 * cp.mastery;
      case ReelFeedback.tooEasy:
        cp.difficultyBias = (cp.difficultyBias + 1).clamp(-2, 2);
        cp.mastery += 0.1 * (1 - cp.mastery);
      case ReelFeedback.gotIt:
        cp.gotItVotes++;
        cp.mastery += 0.08 * (1 - cp.mastery);
    }
    progress.changed();
  }

  bool toggleBookmark(Reel reel) {
    final rs = progress.reel(reel.id);
    rs.bookmarked = !rs.bookmarked;
    progress.changed();
    return rs.bookmarked;
  }
}
