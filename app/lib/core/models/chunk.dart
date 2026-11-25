import '../util/json.dart';

/// A bite-sized section of a [StudySource]; the unit that reels are generated from
/// and that progress is tracked against.
class SourceChunk {
  const SourceChunk({
    required this.id,
    required this.sourceId,
    required this.index,
    required this.title,
    required this.text,
    this.headingPath = const [],
  });

  final String id;
  final String sourceId;

  /// Position inside the source (0-based, reading order).
  final int index;
  final String title;

  /// Headings leading to this chunk, outermost first (e.g. `["Chapter 2", "2.1 Cells"]`).
  final List<String> headingPath;
  final String text;

  int get wordCount => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  String get breadcrumb => headingPath.isEmpty ? title : headingPath.join(' › ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'index': index,
    'title': title,
    'headingPath': headingPath,
    'text': text,
  };

  factory SourceChunk.fromJson(Map<String, dynamic> json) => SourceChunk(
    id: jString(json['id']),
    sourceId: jString(json['sourceId']),
    index: jInt(json['index']),
    title: jString(json['title']),
    headingPath: jStringList(json['headingPath']),
    text: jString(json['text']),
  );
}
