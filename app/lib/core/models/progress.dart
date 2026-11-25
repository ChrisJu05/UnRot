import '../util/json.dart';

enum ChunkStatus { unseen, learning, reviewing, mastered }

/// Learning progress for one [SourceChunk].
class ChunkProgress {
  ChunkProgress({
    required this.chunkId,
    required this.sourceId,
    this.reelsSeen = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.confusedVotes = 0,
    this.gotItVotes = 0,
    this.mastery = 0,
    this.difficultyBias = 0,
    this.firstSeen,
    this.lastSeen,
    List<String>? missedPrompts,
    List<String>? confusingTopics,
  }) : missedPrompts = missedPrompts ?? [],
       confusingTopics = confusingTopics ?? [];

  final String chunkId;
  final String sourceId;
  int reelsSeen;
  int correct;
  int incorrect;
  int confusedVotes;
  int gotItVotes;

  /// Estimated mastery 0..1 (exponential moving average of performance).
  double mastery;

  /// -2 (make it easier) .. +2 (make it harder); driven by learner feedback.
  int difficultyBias;
  DateTime? firstSeen;
  DateTime? lastSeen;

  /// Recently missed questions (fed back to the AI to target weak spots).
  final List<String> missedPrompts;

  /// Topics the learner marked as confusing.
  final List<String> confusingTopics;

  int get answered => correct + incorrect;
  double? get accuracy => answered == 0 ? null : correct / answered;

  ChunkStatus get status {
    if (reelsSeen == 0) return ChunkStatus.unseen;
    if (mastery >= 0.85) return ChunkStatus.mastered;
    if (mastery >= 0.55) return ChunkStatus.reviewing;
    return ChunkStatus.learning;
  }

  void rememberMissed(String prompt) => _pushBounded(missedPrompts, prompt);
  void rememberConfusing(String topic) => _pushBounded(confusingTopics, topic);

  static void _pushBounded(List<String> list, String value, [int max = 8]) {
    if (value.isEmpty) return;
    list.remove(value);
    list.add(value);
    while (list.length > max) {
      list.removeAt(0);
    }
  }

  Map<String, dynamic> toJson() => {
    'chunkId': chunkId,
    'sourceId': sourceId,
    'reelsSeen': reelsSeen,
    'correct': correct,
    'incorrect': incorrect,
    'confusedVotes': confusedVotes,
    'gotItVotes': gotItVotes,
    'mastery': mastery,
    'difficultyBias': difficultyBias,
    'firstSeen': firstSeen?.toIso8601String(),
    'lastSeen': lastSeen?.toIso8601String(),
    'missedPrompts': missedPrompts,
    'confusingTopics': confusingTopics,
  };

  factory ChunkProgress.fromJson(Map<String, dynamic> json) => ChunkProgress(
    chunkId: jString(json['chunkId']),
    sourceId: jString(json['sourceId']),
    reelsSeen: jInt(json['reelsSeen']),
    correct: jInt(json['correct']),
    incorrect: jInt(json['incorrect']),
    confusedVotes: jInt(json['confusedVotes']),
    gotItVotes: jInt(json['gotItVotes']),
    mastery: jDouble(json['mastery']).clamp(0.0, 1.0),
    difficultyBias: jInt(json['difficultyBias']).clamp(-2, 2),
    firstSeen: jDate(json['firstSeen']),
    lastSeen: jDate(json['lastSeen']),
    missedPrompts: jStringList(json['missedPrompts']),
    confusingTopics: jStringList(json['confusingTopics']),
  );
}

/// Interaction + spaced-repetition state for a single reel.
class ReelState {
  ReelState({
    required this.reelId,
    this.views = 0,
    this.lastViewed,
    this.lastCorrect,
    this.bookmarked = false,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.due,
  });

  final String reelId;
  int views;
  DateTime? lastViewed;
  bool? lastCorrect;
  bool bookmarked;

  // --- spaced repetition (SM-2 style) ---
  double ease;
  double intervalDays;
  int repetitions;
  int lapses;

  /// When this reel should be reviewed again; null = not scheduled.
  DateTime? due;

  bool isDue(DateTime now) => due != null && !due!.isAfter(now);

  Map<String, dynamic> toJson() => {
    'reelId': reelId,
    'views': views,
    'lastViewed': lastViewed?.toIso8601String(),
    'lastCorrect': lastCorrect,
    'bookmarked': bookmarked,
    'ease': ease,
    'intervalDays': intervalDays,
    'repetitions': repetitions,
    'lapses': lapses,
    'due': due?.toIso8601String(),
  };

  factory ReelState.fromJson(Map<String, dynamic> json) => ReelState(
    reelId: jString(json['reelId']),
    views: jInt(json['views']),
    lastViewed: jDate(json['lastViewed']),
    lastCorrect: json['lastCorrect'] is bool ? json['lastCorrect'] as bool : null,
    bookmarked: jBool(json['bookmarked']),
    ease: jDouble(json['ease'], 2.5),
    intervalDays: jDouble(json['intervalDays']),
    repetitions: jInt(json['repetitions']),
    lapses: jInt(json['lapses']),
    due: jDate(json['due']),
  );
}

/// Global study statistics (streaks, daily activity).
class StudyStats {
  StudyStats({Map<String, int>? reelsPerDay, this.totalReels = 0, this.totalCorrect = 0, this.totalAnswered = 0})
    : reelsPerDay = reelsPerDay ?? {};

  /// `yyyy-mm-dd` -> reels viewed that day.
  final Map<String, int> reelsPerDay;
  int totalReels;
  int totalCorrect;
  int totalAnswered;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int reelsOn(DateTime day) => reelsPerDay[dayKey(day)] ?? 0;

  /// Consecutive days (ending today, or yesterday if nothing yet today) with activity.
  int streak(DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (reelsOn(day) == 0) day = day.subtract(const Duration(days: 1));
    var count = 0;
    while (reelsOn(day) > 0) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  Map<String, dynamic> toJson() => {
    'reelsPerDay': reelsPerDay,
    'totalReels': totalReels,
    'totalCorrect': totalCorrect,
    'totalAnswered': totalAnswered,
  };

  factory StudyStats.fromJson(Map<String, dynamic> json) => StudyStats(
    reelsPerDay: jMap(json['reelsPerDay']).map((k, v) => MapEntry(k, jInt(v))),
    totalReels: jInt(json['totalReels']),
    totalCorrect: jInt(json['totalCorrect']),
    totalAnswered: jInt(json['totalAnswered']),
  );
}
