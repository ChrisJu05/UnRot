import '../util/json.dart';

/// One imported file (or pasted text) inside a [StudySource].
class SourceDocument {
  SourceDocument({
    required this.id,
    required this.title,
    required this.format,
    required this.addedAt,
    this.fileName,
    this.chunkCount = 0,
    this.charCount = 0,
  });

  /// Unique within the source, e.g. `d1`.
  final String id;
  String title;
  final String format;
  final String? fileName;
  final DateTime addedAt;
  int chunkCount;
  int charCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'format': format,
    'fileName': fileName,
    'addedAt': addedAt.toIso8601String(),
    'chunkCount': chunkCount,
    'charCount': charCount,
  };

  factory SourceDocument.fromJson(Map<String, dynamic> json) => SourceDocument(
    id: jString(json['id'], 'd0'),
    title: jString(json['title'], 'Untitled'),
    format: jString(json['format'], 'text'),
    fileName: jStringOrNull(json['fileName']),
    addedAt: jDate(json['addedAt']) ?? DateTime.now(),
    chunkCount: jInt(json['chunkCount']),
    charCount: jInt(json['charCount']),
  );
}

/// A piece of study material: a single document or a collection of documents
/// (e.g. lecture script + exercise sheets + formula collection of one course).
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
    List<SourceDocument>? documents,
  }) : study = study ?? SourceStudySettings(),
       documents = documents ?? [];

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

  /// Documents in reading order. Sources created before collections existed get
  /// one implicit document (`d0`) when loaded.
  final List<SourceDocument> documents;

  bool get isCollection => documents.length > 1;

  SourceDocument? document(String id) {
    for (final d in documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// A new, unused document id.
  String nextDocumentId() {
    var max = 0;
    for (final d in documents) {
      max = [max, int.tryParse(d.id.substring(1)) ?? 0].reduce((a, b) => a > b ? a : b);
    }
    return 'd${max + 1}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'format': format,
    'originalFileName': originalFileName,
    'addedAt': addedAt.toIso8601String(),
    'chunkCount': chunkCount,
    'charCount': charCount,
    'study': study.toJson(),
    'documents': documents.map((d) => d.toJson()).toList(),
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
    documents: (json['documents'] is List ? json['documents'] as List : const [])
        .map((e) => SourceDocument.fromJson(jMap(e)))
        .toList(),
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
    this.subjectId = 'general',
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

  /// Subject profile id (see `SubjectProfiles`), e.g. `signal_theory`.
  String subjectId;

  SourceStudySettings copy() => SourceStudySettings.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'modeId': modeId,
    'includeInFeed': includeInFeed,
    'feedWeight': feedWeight,
    'examDate': examDate?.toIso8601String(),
    'focusNote': focusNote,
    'reelLanguage': reelLanguage,
    'subjectId': subjectId,
  };

  factory SourceStudySettings.fromJson(Map<String, dynamic> json) => SourceStudySettings(
    modeId: jString(json['modeId'], 'linear'),
    includeInFeed: jBool(json['includeInFeed'], true),
    feedWeight: jDouble(json['feedWeight'], 1.0).clamp(0.0, 10.0),
    examDate: jDate(json['examDate']),
    focusNote: jString(json['focusNote']),
    reelLanguage: jString(json['reelLanguage'], 'default'),
    subjectId: jString(json['subjectId'], 'general'),
  );
}
