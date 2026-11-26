import '../util/json.dart';

/// One short, swipeable piece of learning content.
///
/// The type-specific payload lives in [data]; its shape is defined and validated
/// by the matching `ReelTypeSpec` (see `modules/reels/reel_types.dart`).
class Reel {
  Reel({
    required this.id,
    required this.sourceId,
    required this.chunkId,
    required this.type,
    required this.data,
    required this.createdAt,
    this.generator = 'unknown',
    this.difficulty = 2,
    this.parentReelId,
    this.language,
  });

  final String id;
  final String sourceId;
  final String chunkId;

  /// Reel type id, e.g. `explainer`, `quiz`, `flashcard`.
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  /// Which generator produced it, e.g. `anthropic:claude-opus-5-5` or `offline`.
  final String generator;

  /// 1 = easy, 2 = medium, 3 = hard.
  final int difficulty;

  /// Set for "explain more" follow-ups.
  final String? parentReelId;

  /// Language the reel was written in (`source` or a language name); null for old reels.
  final String? language;

  String str(String key) => jString(data[key]);
  List<String> list(String key) => jStringList(data[key]);

  /// Short human readable summary used to avoid repetition in prompts.
  String get summary {
    for (final key in const ['title', 'question', 'statement', 'front', 'prompt', 'concept', 'text']) {
      final value = str(key);
      if (value.isNotEmpty) return value.length > 140 ? '${value.substring(0, 140)}…' : value;
    }
    return type;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'chunkId': chunkId,
    'type': type,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'generator': generator,
    'difficulty': difficulty,
    if (parentReelId != null) 'parentReelId': parentReelId,
    if (language != null) 'language': language,
  };

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
    id: jString(json['id']),
    sourceId: jString(json['sourceId']),
    chunkId: jString(json['chunkId']),
    type: jString(json['type']),
    data: jMap(json['data']),
    createdAt: jDate(json['createdAt']) ?? DateTime.now(),
    generator: jString(json['generator'], 'unknown'),
    difficulty: jInt(json['difficulty'], 2),
    parentReelId: jStringOrNull(json['parentReelId']),
    language: jStringOrNull(json['language']),
  );
}
