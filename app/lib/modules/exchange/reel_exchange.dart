import 'dart:convert';

import '../../core/models/chunk.dart';
import '../../core/models/reel.dart';
import '../../core/models/settings.dart';
import '../../core/models/source.dart';
import '../../core/util/ids.dart';
import '../../core/util/json.dart';
import '../generation/generation_job.dart';
import '../generation/prompt_builder.dart';
import '../generation/reel_parser.dart';
import '../reels/reel_types.dart';
import '../study/study_mode.dart';

/// Result of importing reels from a chat answer or a JSON file.
class ReelImportReport {
  ReelImportReport(this.reels, this.skipped, this.problems);
  final List<Reel> reels;
  final int skipped;
  final List<String> problems;
}

/// Lets learners use a chat subscription (Claude Pro, ChatGPT Plus, Gemini …)
/// instead of an API key: UnRot builds a prompt to paste into the chat, and
/// imports the JSON answer as reels. The same JSON format is used for files.
///
/// Format:
/// ```json
/// {"unrot_reels": 1, "reels": [{"section": 3, "type": "quiz", ...}, ...]}
/// ```
/// `section` is the 1-based section number shown in UnRot.
class ReelExchange {
  const ReelExchange({this.prompts = const PromptBuilder()});

  final PromptBuilder prompts;

  /// Recommended upper limit for the pasted prompt (most chat UIs handle more).
  static const maxPromptChars = 60000;

  /// Reel types worth asking for, most important first.
  static List<String> typesFor(StudyMode mode, Map<String, double> subjectMix, GenerationSettings settings) {
    final weights = <String, double>{...mode.defaultReelMix};
    subjectMix.forEach((k, v) => weights[k] = (weights[k] ?? 0) + v);
    if (settings.visualWeightFactor == 0) weights.remove('visual');
    final types = weights.entries.where((e) => e.value > 0 && ReelTypes.byId(e.key) != null).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return types.map((e) => e.key).toList();
  }

  String buildPrompt({
    required StudySource source,
    required List<SourceChunk> sections,
    required StudyMode mode,
    required GenerationSettings settings,
    required List<String> types,
    int reelsPerSection = 6,
  }) {
    if (sections.isEmpty) return '';
    final job = GenerationJob(
      source: source,
      chunk: sections.first,
      chunkCount: sections.length,
      reelTypes: types,
      mode: mode,
      settings: settings,
    );
    final b = StringBuffer()
      ..writeln(prompts.system(job).replaceFirst('- Reply with JSON only, exactly in the requested format.', ''))
      ..writeln()
      ..writeln('STUDY MODE: ${mode.name}. ${mode.promptGuidance}')
      ..writeln('SOURCE: "${source.title}"');
    if (job.subject.guidance.isNotEmpty) b.writeln('SUBJECT: ${job.subject.guidance}');
    if (source.study.focusNote.trim().isNotEmpty) b.writeln('LEARNER FOCUS: ${source.study.focusNote.trim()}');
    if (settings.customInstructions.trim().isNotEmpty) {
      b.writeln('EXTRA INSTRUCTIONS FROM THE LEARNER: ${settings.customInstructions.trim()}');
    }
    b
      ..writeln()
      ..writeln(
        'TASK: For EACH section below create $reelsPerSection reels. Mix these types (most useful first, use a type '
        'only where it fits the content): ${types.join(', ')}.',
      )
      ..writeln('Reel formats:');
    for (final id in types) {
      final spec = ReelTypes.byId(id);
      if (spec == null) continue;
      b
        ..writeln('- ${spec.id}: ${spec.promptFormat}')
        ..writeln('  (${spec.promptGuidance})');
    }
    b
      ..writeln()
      ..writeln('Reply with ONE json code block and nothing else, in exactly this shape:')
      ..writeln(
        '{"unrot_reels": 1, "reels": [{"section": <section number>, "type": "...", ...fields of that type...}]}',
      )
      ..writeln('Every reel must contain the "section" number it belongs to.')
      ..writeln();
    for (final c in sections) {
      b.writeln('SECTION ${c.index + 1}: ${c.breadcrumb}');
      if (c.images.isNotEmpty) {
        b.writeln(
          '(figures: ${c.images.map((i) => '${i.id}${i.caption.isEmpty ? '' : ' = ${i.caption}'}').join('; ')})',
        );
      }
      b
        ..writeln('<<<')
        ..writeln(c.plainText)
        ..writeln('>>>')
        ..writeln();
    }
    return b.toString();
  }

  /// Parses a pasted chat answer or a JSON file into reels for [source].
  ReelImportReport parseAnswer(
    String text, {
    required StudySource source,
    required List<SourceChunk> chunks,
    required GenerationSettings settings,
    Iterable<Reel> existing = const [],
  }) {
    final problems = <String>[];
    final json = ReelParser.extractJson(text);
    List raw;
    if (json is List) {
      raw = json;
    } else if (json is Map && json['reels'] is List) {
      raw = json['reels'] as List;
    } else {
      return ReelImportReport(const [], 0, ['No reels found. Paste the whole answer including the JSON block.']);
    }
    final bySection = {for (final c in chunks) c.index + 1: c};
    final byId = {for (final c in chunks) c.id: c};
    final language = GenerationJob.effectiveLanguage(source, settings);
    final seen = {for (final r in existing) '${r.chunkId}|${r.type}|${r.summary}'};
    final reels = <Reel>[];
    var skipped = 0;
    for (final item in raw) {
      final m = jMap(item);
      final chunk = bySection[jInt(m['section'], -1)] ?? byId[jString(m['section_id'])];
      if (chunk == null) {
        skipped++;
        if (problems.length < 5) problems.add('Unknown section "${m['section']}"');
        continue;
      }
      final normalized = ReelParser.normalizeReel(m);
      if (normalized == null) {
        skipped++;
        if (problems.length < 5) problems.add('Invalid ${jString(m['type'], 'reel')} in section ${chunk.index + 1}');
        continue;
      }
      final (type, data) = normalized;
      final reel = Reel(
        id: newId('r'),
        sourceId: source.id,
        chunkId: chunk.id,
        type: type,
        data: data,
        createdAt: DateTime.now(),
        generator: 'import:chat',
        language: language,
      );
      if (!seen.add('${chunk.id}|$type|${reel.summary}')) {
        skipped++;
        continue;
      }
      reels.add(reel);
    }
    return ReelImportReport(reels, skipped, problems);
  }

  /// Exports reels in the same format (e.g. to move them to another device).
  String exportReels(List<Reel> reels, List<SourceChunk> chunks) {
    final indexById = {for (final c in chunks) c.id: c.index + 1};
    return const JsonEncoder.withIndent(' ').convert({
      'unrot_reels': 1,
      'reels': [
        for (final r in reels)
          if (indexById[r.chunkId] != null) {'section': indexById[r.chunkId], 'type': r.type, ...r.data},
      ],
    });
  }
}
