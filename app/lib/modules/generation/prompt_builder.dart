import '../reels/reel_types.dart';
import 'generation_job.dart';

/// Builds provider-neutral prompts for reel generation.
class PromptBuilder {
  const PromptBuilder();

  static const _styles = {
    'friendly': 'warm, encouraging and conversational, like a great tutor',
    'concise': 'crisp and to the point, no filler',
    'academic': 'precise and formal, using correct technical terminology',
    'playful': 'fun and witty with vivid images, while staying accurate',
    'eli5': 'very simple words and everyday analogies, as if explaining to a curious 12-year-old',
  };

  static const _difficulty = {
    1: 'easy — focus on core ideas and recognition',
    2: 'medium — understanding and connections',
    3: 'hard — application, transfer, edge cases and precise details',
  };

  String system(GenerationJob job) {
    final s = job.settings;
    final lang = job.language;
    final language = lang == 'source'
        ? 'the same language as the source excerpt'
        : '$lang. If the source is in another language, translate everything into $lang; the first time a key '
              'technical term appears, add the original term in brackets (useful for exams in the original language)';
    return [
      'You are UnRot, an expert tutor who turns study material into short, swipeable, interactive "reels" '
          '(like TikTok or Instagram reels, but for learning).',
      'Rules:',
      '- Ground every reel strictly in the SOURCE EXCERPT. Do not add facts the source does not support. '
          'If the excerpt does not contain enough material for a requested reel, return fewer reels.',
      '- Each reel must stand on its own and be consumable in 10-30 seconds.',
      '- Keep every text field short: at most ${s.maxWordsPerReel} words.',
      '- Write in $language.',
      '- Tone: ${_styles[s.style] ?? s.style}.',
      s.useEmojis
          ? '- Use at most one fitting emoji per reel (in the "emoji" field where available).'
          : '- Do not use emojis; leave emoji fields empty.',
      '- You may use **bold** for key terms. No headings, no HTML.',
      r'- Write math in LaTeX: inline $\frac{a}{b}$, display $$E = mc^2$$. Escape backslashes in JSON ("\\frac").',
      '- Reply with JSON only, exactly in the requested format.',
    ].join('\n');
  }

  String user(GenerationJob job) {
    final buffer = StringBuffer();
    final chunk = job.chunk;
    buffer.writeln('STUDY MODE: ${job.mode.name}. ${job.mode.promptGuidance}');
    buffer.writeln('DIFFICULTY: ${_difficulty[job.difficulty]}.');
    buffer.writeln(
      'SOURCE: "${job.source.title}", section ${chunk.index + 1} of ${job.chunkCount}: ${chunk.breadcrumb}',
    );
    if (job.previousChunkTitle != null) buffer.writeln('PREVIOUS SECTION: ${job.previousChunkTitle}');
    final p = job.progress;
    if (p != null && p.reelsSeen > 0) {
      buffer.writeln(
        'LEARNER PROGRESS ON THIS SECTION: ${p.reelsSeen} reels seen, '
        'mastery ${(p.mastery * 100).round()}%'
        '${p.accuracy != null ? ', ${(p.accuracy! * 100).round()}% of answers correct' : ''}.',
      );
      if (p.missedPrompts.isNotEmpty) {
        buffer.writeln('The learner got these wrong recently — target these weak spots from a new angle:');
        for (final m in p.missedPrompts.reversed.take(5)) {
          buffer.writeln('  - $m');
        }
      }
      if (p.confusingTopics.isNotEmpty) {
        buffer.writeln('The learner found these confusing — explain them more simply:');
        for (final m in p.confusingTopics.reversed.take(4)) {
          buffer.writeln('  - $m');
        }
      }
    }
    if (job.existingSummaries.isNotEmpty) {
      buffer.writeln('ALREADY COVERED (do not repeat these; find new angles or details):');
      for (final s in job.existingSummaries.take(15)) {
        buffer.writeln('  - $s');
      }
    }
    if (job.source.study.focusNote.trim().isNotEmpty) {
      buffer.writeln('LEARNER FOCUS FOR THIS SOURCE: ${job.source.study.focusNote.trim()}');
    }
    if (job.focus != null) {
      buffer.writeln(
        'GO DEEPER: The learner tapped "explain more" on this reel. Expand on it, add examples, '
        'and clarify what is behind it:\n  "${job.focus}"',
      );
    }
    if (job.settings.customInstructions.trim().isNotEmpty) {
      buffer.writeln('EXTRA INSTRUCTIONS FROM THE LEARNER: ${job.settings.customInstructions.trim()}');
    }
    buffer.writeln();
    buffer.writeln(
      'Create ${job.reelTypes.length} reels with these types, in this order: ${job.reelTypes.join(', ')}.',
    );
    buffer.writeln('Formats:');
    for (final id in job.reelTypes.toSet()) {
      final spec = ReelTypes.byId(id);
      if (spec == null) continue;
      buffer.writeln('- ${spec.id}: ${spec.promptFormat}');
      buffer.writeln('  (${spec.promptGuidance})');
    }
    buffer.writeln();
    buffer.writeln('Return exactly: {"reels": [ ...reel objects... ]}');
    buffer.writeln();
    if (chunk.images.isNotEmpty) {
      buffer.writeln(
        'FIGURES IN THIS SECTION (can be shown with a visual reel of kind "image"; you cannot see them, '
        'rely on the caption and surrounding text):',
      );
      for (final img in chunk.images) {
        buffer.writeln('  - ${img.id}: ${img.caption.isEmpty ? '(no caption)' : img.caption}');
      }
      buffer.writeln();
    }
    buffer.writeln('SOURCE EXCERPT:');
    buffer.writeln('<<<');
    buffer.writeln(chunk.plainText);
    buffer.writeln('>>>');
    return buffer.toString();
  }

  /// JSON schema for structured outputs, restricted to the requested types.
  /// Null when a requested type is free-form (e.g. visuals).
  Map<String, Object?>? schema(GenerationJob job) {
    final specs = job.reelTypes.toSet().map(ReelTypes.byId).whereType<ReelTypeSpec>().toList();
    if (specs.isEmpty || specs.any((s) => s.jsonSchema == null)) return null;
    final items = specs.length == 1 ? specs.first.jsonSchema! : {'anyOf': specs.map((s) => s.jsonSchema!).toList()};
    return {
      'type': 'object',
      'properties': {
        'reels': {'type': 'array', 'items': items},
      },
      'required': ['reels'],
      'additionalProperties': false,
    };
  }
}
