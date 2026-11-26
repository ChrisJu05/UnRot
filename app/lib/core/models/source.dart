import '../util/json.dart';

/// A piece of study material the user imported (script, book, notes, ...).
class StudySource {
  StudySource({
    required this.id,
    required this.title,
    required this.format,
    required this.addedAt,
    this.originalFileName,
    this.chunkCount = 0,
    this.charCount = 0,
    SourceStudySettings? study,
  }) : study = study ?? SourceStudySettings();

  final String id;
  String title;

  /// Extractor id that produced the text: `pdf`, `text`, `markdown`, `epub`, `docx`, `html`, `paste`.
  final String format;
  final String? originalFileName;
  final DateTime addedAt;
  int chunkCount;
  int charCount;

  /// How this source is studied and how much of the feed it gets.
  SourceStudySettings study;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'format': format,
    'originalFileName': originalFileName,
    'addedAt': addedAt.toIso8601String(),
    'chunkCount': chunkCount,
    'charCount': charCount,
    'study': study.toJson(),
  };

  factory StudySource.fromJson(Map<String, dynamic> json) => StudySource(
    id: jString(json['id']),
    title: jString(json['title'], 'Untitled'),
    format: jString(json['format'], 'text'),
    originalFileName: jStringOrNull(json['originalFileName']),
    addedAt: jDate(json['addedAt']) ?? DateTime.now(),
    chunkCount: jInt(json['chunkCount']),
    charCount: jInt(json['charCount']),
    study: SourceStudySettings.fromJson(jMap(json['study'])),
  );
}

/// Per-source study configuration.
class SourceStudySettings {
  SourceStudySettings({
    this.modeId = 'linear',
    this.includeInFeed = true,
    this.feedWeight = 1.0,
    this.examDate,
    this.focusNote = '',
    this.reelLanguage = 'default',
  });

  /// Id of a registered [StudyMode] (`linear`, `exam`, `rote`, `explore`, ...).
  String modeId;

  /// Whether reels from this source appear in the main feed.
  bool includeInFeed;

  /// Relative share of the feed (normalised against all included sources).
  double feedWeight;

  /// Exam date for exam-prep mode (used for pacing).
  DateTime? examDate;

  /// Free-text hint for the generator ("focus on formulas", "skip chapter 1").
  String focusNote;

  /// Language of the reels for this source: `default` (app setting), `source`
  /// (same as the material) or a language name such as `English`.
  String reelLanguage;

  SourceStudySettings copy() => SourceStudySettings.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'modeId': modeId,
    'includeInFeed': includeInFeed,
    'feedWeight': feedWeight,
    'examDate': examDate?.toIso8601String(),
    'focusNote': focusNote,
    'reelLanguage': reelLanguage,
  };

  factory SourceStudySettings.fromJson(Map<String, dynamic> json) => SourceStudySettings(
    modeId: jString(json['modeId'], 'linear'),
    includeInFeed: jBool(json['includeInFeed'], true),
    feedWeight: jDouble(json['feedWeight'], 1.0).clamp(0.0, 10.0),
    examDate: jDate(json['examDate']),
    focusNote: jString(json['focusNote']),
    reelLanguage: jString(json['reelLanguage'], 'default'),
  );
}
