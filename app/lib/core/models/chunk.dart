import '../util/json.dart';

/// Figure markers inside chunk text: `[[img:img3|Figure 3: The cell membrane]]`.
final figureMarker = RegExp(r'\[\[img:([A-Za-z0-9_-]+)(?:\|([^\]]*))?\]\]');

/// A figure (image) extracted from the source that belongs to a chunk.
class ChunkImage {
  const ChunkImage({required this.id, required this.file, this.caption = ''});

  /// Id referenced by reels, e.g. `img3`.
  final String id;

  /// File name inside the source's image folder, e.g. `img3.jpg`.
  final String file;
  final String caption;

  Map<String, dynamic> toJson() => {'id': id, 'file': file, 'caption': caption};

  factory ChunkImage.fromJson(Map<String, dynamic> json) =>
      ChunkImage(id: jString(json['id']), file: jString(json['file']), caption: jString(json['caption']));
}

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
    this.images = const [],
    this.documentId = 'd0',
  });

  final String id;
  final String sourceId;

  /// The [SourceDocument] this section comes from.
  final String documentId;

  /// Position inside the source (0-based, reading order).
  final int index;
  final String title;

  /// Headings leading to this chunk, outermost first (e.g. `["Chapter 2", "2.1 Cells"]`).
  final List<String> headingPath;

  /// Text of the section; figures appear as `[[img:…]]` markers.
  final String text;

  /// Figures that appear in this section.
  final List<ChunkImage> images;

  int get wordCount => plainText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  String get breadcrumb => headingPath.isEmpty ? title : headingPath.join(' › ');

  /// Text with figure markers replaced by readable placeholders.
  String get plainText => text.replaceAllMapped(figureMarker, (m) {
    final caption = (m[2] ?? '').trim();
    return caption.isEmpty ? '[Figure ${m[1]}]' : '[Figure ${m[1]}: $caption]';
  });

  SourceChunk copyWith({List<ChunkImage>? images, int? index}) => SourceChunk(
    id: id,
    sourceId: sourceId,
    index: index ?? this.index,
    title: title,
    text: text,
    headingPath: headingPath,
    images: images ?? this.images,
    documentId: documentId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'index': index,
    'title': title,
    'headingPath': headingPath,
    'text': text,
    if (images.isNotEmpty) 'images': images.map((i) => i.toJson()).toList(),
    'documentId': documentId,
  };

  factory SourceChunk.fromJson(Map<String, dynamic> json) => SourceChunk(
    id: jString(json['id']),
    sourceId: jString(json['sourceId']),
    index: jInt(json['index']),
    title: jString(json['title']),
    headingPath: jStringList(json['headingPath']),
    text: jString(json['text']),
    documentId: jString(json['documentId'], 'd0'),
    images: (json['images'] is List ? json['images'] as List : const [])
        .map((e) => ChunkImage.fromJson(jMap(e)))
        .toList(),
  );
}
