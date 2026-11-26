import 'package:flutter_test/flutter_test.dart';
import 'package:unrot/core/models/chunk.dart';
import 'package:unrot/core/models/progress.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/models/source.dart';
import 'package:unrot/modules/generation/generation_job.dart';
import 'package:unrot/modules/generation/offline_generator.dart';
import 'package:unrot/modules/generation/prompt_builder.dart';
import 'package:unrot/modules/generation/reel_parser.dart';
import 'package:unrot/modules/reels/reel_types.dart';
import 'package:unrot/modules/study/modes/builtin_modes.dart';

const sampleText =
    'Mitochondria are the powerhouse of the cell. They produce ATP through cellular respiration. '
    'Mitochondria have their own DNA, which supports the endosymbiotic theory. The inner membrane is folded '
    'into cristae to increase the surface area for the electron transport chain. Oxygen is the final electron '
    'acceptor in the electron transport chain. Without oxygen, cells rely on fermentation to regenerate NAD+.';

GenerationJob job(List<String> types, {ChunkProgress? progress, GenerationSettings? settings, String? focus}) {
  final source = StudySource(id: 's1', title: 'Biology', format: 'text', addedAt: DateTime(2026));
  return GenerationJob(
    source: source,
    chunk: const SourceChunk(
      id: 's1:3',
      sourceId: 's1',
      index: 3,
      title: 'Mitochondria',
      text: sampleText,
      headingPath: ['Cells', 'Mitochondria'],
    ),
    chunkCount: 10,
    reelTypes: types,
    mode: const LinearMode(),
    settings: settings ?? GenerationSettings(),
    progress: progress,
    focus: focus,
  );
}

void main() {
  group('ReelTypes.normalize', () {
    test('quiz accepts answer text instead of index and rejects bad indices', () {
      final quiz = ReelTypes.byId('quiz')!;
      expect(
        quiz.normalize({
          'question': 'Q?',
          'options': ['a', 'b', 'c'],
          'answer': 'b',
        })!['answer_index'],
        1,
      );
      expect(
        quiz.normalize({
          'question': 'Q?',
          'options': ['a', 'b'],
          'answer_index': 5,
        }),
        isNull,
      );
    });

    test('cloze inserts a gap when the model forgot it', () {
      final cloze = ReelTypes.byId('cloze')!;
      expect(
        cloze.normalize({'text': 'ATP is made by mitochondria.', 'answer': 'mitochondria'})!['text'],
        'ATP is made by ____.',
      );
      expect(
        cloze.normalize({'text': 'The {{nucleus}} holds DNA.', 'answer': 'nucleus'})!['text'],
        'The ____ holds DNA.',
      );
      expect(cloze.normalize({'text': 'No answer inside.', 'answer': 'xyz'}), isNull);
    });

    test('true/false accepts string booleans', () {
      expect(ReelTypes.byId('true_false')!.normalize({'statement': 'S', 'answer': 'True'})!['answer'], isTrue);
    });

    test('every schema-based type has a closed JSON schema', () {
      for (final t in ReelTypes.all) {
        final schema = t.jsonSchema;
        if (schema == null) continue; // free-form types (visual)
        expect(schema['additionalProperties'], isFalse, reason: t.id);
        expect((schema['required'] as List).toSet(), (schema['properties'] as Map).keys.toSet(), reason: t.id);
      }
    });
  });

  group('ReelParser', () {
    const parser = ReelParser();

    test('parses fenced JSON with prose around it', () {
      const text =
          'Sure! Here are your reels:\n```json\n{"reels":[{"type":"explainer","title":"T","body":"A body that is long enough."}]}\n```\nEnjoy!';
      final reels = parser.parse(text, job(['explainer']), generator: 'test');
      expect(reels.single.type, 'explainer');
      expect(reels.single.chunkId, 's1:3');
      expect(reels.single.generator, 'test');
    });

    test('accepts a bare array and maps type aliases', () {
      const text =
          '[{"type":"multiple-choice","question":"Q?","options":["a","b","c","d"],"answer_index":2,"explanation":"e"}]';
      expect(parser.parse(text, job(['quiz']), generator: 't').single.type, 'quiz');
    });

    test('salvages complete objects from truncated output', () {
      const text =
          '{"reels":[{"type":"flashcard","front":"F1","back":"B1","hint":""},{"type":"flashcard","front":"F2","back":"B2","hint":""},{"type":"flashcard","front":"F3","ba';
      final reels = parser.parse(text, job(['flashcard', 'flashcard', 'flashcard']), generator: 't');
      expect(reels.map((r) => r.str('front')), ['F1', 'F2']);
    });

    test('drops invalid reels and unknown types but accepts substituted known types', () {
      const text =
          '{"reels":[{"type":"quiz","question":"","options":[]},{"type":"mnemonic","concept":"c","hook":"h"},'
          '{"type":"hologram","x":1}]}';
      final reels = parser.parse(text, job(['quiz']), generator: 't');
      expect(reels.map((r) => r.type), ['mnemonic']);
    });
  });

  group('PromptBuilder', () {
    test('includes mode, progress, settings and schema for requested types only', () {
      final progress =
          ChunkProgress(chunkId: 's1:3', sourceId: 's1', reelsSeen: 6, mastery: 0.4, correct: 2, incorrect: 3)
            ..rememberMissed('What do mitochondria produce?')
            ..rememberConfusing('cristae');
      final j = job(
        ['explainer', 'quiz'],
        progress: progress,
        settings: GenerationSettings(
          language: 'Deutsch',
          maxWordsPerReel: 40,
          customInstructions: 'Use sports analogies',
        ),
      );
      const builder = PromptBuilder();
      final system = builder.system(j);
      final user = builder.user(j);
      expect(system, contains('Deutsch'));
      expect(system, contains('at most 40 words'));
      expect(user, contains('Linear course'));
      expect(user, contains('section 4 of 10: Cells › Mitochondria'));
      expect(user, contains('What do mitochondria produce?'));
      expect(user, contains('cristae'));
      expect(user, contains('Use sports analogies'));
      expect(user, contains(sampleText));
      final schema = builder.schema(j)!;
      final anyOf = ((schema['properties'] as Map)['reels'] as Map)['items'] as Map;
      expect((anyOf['anyOf'] as List).length, 2);
    });

    test('adaptive difficulty follows mastery and feedback', () {
      expect(job(['quiz']).difficulty, 1);
      expect(
        job(['quiz'], progress: ChunkProgress(chunkId: 'c', sourceId: 's', reelsSeen: 5, mastery: 0.9)).difficulty,
        3,
      );
      expect(
        job(
          ['quiz'],
          progress: ChunkProgress(chunkId: 'c', sourceId: 's', reelsSeen: 5, mastery: 0.9, difficultyBias: -2),
        ).difficulty,
        1,
      );
      expect(job(['quiz'], settings: GenerationSettings(difficulty: 'hard')).difficulty, 3);
    });
  });

  group('OfflineReelGenerator', () {
    test('explain more builds a deep dive around the focused content', () async {
      final reels = await OfflineReelGenerator().generate(
        job(['explainer'], focus: 'Oxygen is the final electron acceptor in the electron transport chain.'),
      );
      expect(reels, isNotEmpty);
      expect(reels.first.str('title'), startsWith('Deep dive'));
      expect(reels.first.str('body'), contains('Oxygen'));
    });

    test('produces valid reels of the requested types without duplicates', () async {
      final types = [
        'explainer',
        'explainer',
        'key_points',
        'quiz',
        'cloze',
        'flashcard',
        'true_false',
        'write_recall',
        'mnemonic',
      ];
      final reels = await OfflineReelGenerator().generate(job(types));
      expect(reels.length, greaterThanOrEqualTo(7));
      for (final r in reels) {
        final spec = ReelTypes.byId(r.type)!;
        expect(spec.normalize(Map.of(r.data)), isNotNull, reason: '${r.type}: ${r.data}');
      }
      final summaries = reels.map((r) => '${r.type}|${r.summary}').toList();
      expect(summaries.toSet().length, summaries.length);
      final quiz = reels.where((r) => r.type == 'quiz');
      if (quiz.isNotEmpty) {
        final q = quiz.first;
        expect(q.list('options')[q.data['answer_index'] as int], isNotEmpty);
      }
    });
  });
}
