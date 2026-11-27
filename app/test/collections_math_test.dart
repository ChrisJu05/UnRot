import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unrot/app/app_services.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/models/source.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/core/storage/secret_store.dart';
import 'package:unrot/core/storage/settings_repository.dart';
import 'package:unrot/modules/ai/provider_registry.dart';
import 'package:unrot/modules/exchange/reel_exchange.dart';
import 'package:unrot/modules/feed/feed_engine.dart';
import 'package:unrot/modules/generation/generation_job.dart';
import 'package:unrot/modules/generation/generation_service.dart';
import 'package:unrot/modules/generation/offline_generator.dart';
import 'package:unrot/modules/generation/reel_parser.dart';
import 'package:unrot/modules/ingestion/chunker.dart';
import 'package:unrot/modules/ingestion/ingestion_service.dart';
import 'package:unrot/modules/ingestion/text_extractor.dart';
import 'package:unrot/modules/reels/reel_types.dart';
import 'package:unrot/modules/speech/speech_engine.dart';
import 'package:unrot/modules/study/modes/builtin_modes.dart';
import 'package:unrot/modules/study/progress_tracker.dart';
import 'package:unrot/modules/study/study_mode.dart';
import 'package:unrot/modules/study/subjects.dart';
import 'package:unrot/ui/reels/math_reels.dart';
import 'package:unrot/ui/reels/reel_widgets.dart';

String notes(String topic, {int sections = 2}) => List.generate(
  sections,
  (i) =>
      '## $topic ${i + 1}\n\n${List.generate(12, (j) => '$topic fact $j of part ${i + 1} explains a detail about $topic.').join(' ')}',
).join('\n\n');

class Env {
  Env(this.dir, this.store, this.settings, this.library, this.reels, this.progress, this.feed, this.ingestion);
  final Directory dir;
  final JsonStore store;
  final SettingsRepository settings;
  final LibraryRepository library;
  final ReelRepository reels;
  final ProgressRepository progress;
  final FeedEngine feed;
  final IngestionService ingestion;
  DateTime now = DateTime(2026, 11, 25, 10);

  static Future<Env> create() async {
    final dir = await Directory.systemTemp.createTemp('unrot_coll');
    final store = JsonStore(dir);
    final settings = SettingsRepository(store, MemorySecretStore());
    final library = LibraryRepository(store);
    final reels = ReelRepository(store);
    final progress = ProgressRepository(store);
    late Env env;
    final feed = FeedEngine(
      library: library,
      reels: reels,
      progress: progress,
      settings: settings,
      generation: GenerationService(settings, ProviderRegistry()),
      modes: StudyModes(builtinStudyModes()),
      tracker: ProgressTracker(progress),
      random: Random(3),
      clock: () => env.now,
    );
    env = Env(dir, store, settings, library, reels, progress, feed, IngestionService(library));
    return env;
  }

  Reel addReel(StudySource source, String id, {String type = 'explainer', int chunk = 0, String? language}) {
    final r = Reel(
      id: id,
      sourceId: source.id,
      chunkId: library.chunks(source.id)[chunk].id,
      type: type,
      data: {'title': id, 'body': 'Body of $id'},
      createdAt: now,
      language: language,
    );
    reels.addAll([r]);
    return r;
  }
}

GenerationJob job(StudySource source, String text, List<String> types, {String language = 'source'}) {
  final chunk = const Chunker().chunk(source.id, text).first;
  return GenerationJob(
    source: source,
    chunk: chunk,
    chunkCount: 1,
    reelTypes: types,
    mode: const ExploreMode(),
    settings: GenerationSettings(language: language),
  );
}

void main() {
  group('Collections', () {
    test('documents are added, ordered, moved and removed', () async {
      final env = await Env.create();
      final collection = await env.ingestion.createCollection('Signaltheorie');
      expect(collection.format, 'collection');
      expect(env.library.chunks(collection.id), isEmpty);

      final a = await env.ingestion.importText('Skript', notes('Fourier'), intoSourceId: collection.id);
      final b = await env.ingestion.importText(
        'Übungsblatt 1',
        notes('Laplace', sections: 3),
        intoSourceId: collection.id,
      );
      expect(a.source.id, collection.id);
      expect(a.document!.id, 'd1');
      expect(b.document!.id, 'd2');
      final source = env.library.source(collection.id)!;
      expect(source.isCollection, isTrue);
      expect(source.documents.map((d) => d.title), ['Skript', 'Übungsblatt 1']);
      expect(source.documents.map((d) => d.chunkCount), [2, 3]);
      expect(source.chunkCount, 5);

      var chunks = env.library.chunks(collection.id);
      expect(chunks.map((c) => c.index), [0, 1, 2, 3, 4]);
      expect(chunks.map((c) => c.documentId), ['d1', 'd1', 'd2', 'd2', 'd2']);
      expect(chunks.first.id, startsWith('${collection.id}:d1-'));
      expect(chunks.last.id, startsWith('${collection.id}:d2-'));
      expect(env.library.documentOf(chunks.last)!.title, 'Übungsblatt 1');

      // Move the exercise sheet first: indexes follow, ids stay.
      final ids = chunks.map((c) => c.id).toSet();
      await env.library.moveDocument(collection.id, 'd2', -1);
      chunks = env.library.chunks(collection.id);
      expect(chunks.map((c) => c.documentId), ['d2', 'd2', 'd2', 'd1', 'd1']);
      expect(chunks.map((c) => c.index), [0, 1, 2, 3, 4]);
      expect(chunks.map((c) => c.id).toSet(), ids);

      // Survives a restart.
      final reloaded = LibraryRepository(env.store);
      await env.store.flush();
      await reloaded.load();
      expect(reloaded.source(collection.id)!.documents.map((d) => d.id), ['d2', 'd1']);
      expect(reloaded.chunks(collection.id).first.documentId, 'd2');

      final removed = await env.library.removeDocument(collection.id, 'd2');
      expect(removed, hasLength(3));
      expect(env.library.chunks(collection.id).map((c) => c.documentId), ['d1', 'd1']);
      expect(env.library.chunks(collection.id).map((c) => c.index), [0, 1]);
      expect(env.library.source(collection.id)!.chunkCount, 2);
      expect(env.library.source(collection.id)!.nextDocumentId(), 'd2');
    });

    test('a single import is a source with one document; legacy sources get d0', () async {
      final env = await Env.create();
      final single = await env.ingestion.importText('Notes', notes('Bio'));
      expect(single.source.documents.single.id, 'd1');
      expect(single.source.isCollection, isFalse);

      // A library written before collections existed.
      await env.store.write('library.json', {
        'sources': [
          {'id': 'old', 'title': 'Old book', 'format': 'pdf', 'addedAt': '2026-01-01T00:00:00.000'},
        ],
      });
      await env.store.write('chunks/old.json', [
        {'id': 'old:0', 'sourceId': 'old', 'index': 0, 'title': 'Intro', 'text': 'Some old text about things.'},
        {'id': 'old:1', 'sourceId': 'old', 'index': 1, 'title': 'More', 'text': 'Some more old text.'},
      ]);
      await env.store.flush();
      final legacy = LibraryRepository(env.store);
      await legacy.load();
      final old = legacy.source('old')!;
      expect(old.documents.single.id, 'd0');
      expect(old.documents.single.title, 'Old book');
      expect(old.documents.single.chunkCount, 2);
      expect(legacy.chunks('old').every((c) => c.documentId == 'd0'), isTrue);
      expect(old.nextDocumentId(), 'd1');
    });

    test('figure ids are prefixed per document so they never collide', () {
      final doc = ExtractedDocument(
        title: 'T',
        text: 'Intro text.\n\n[[img:p1-0|Bode plot]]\n\nMore.',
        images: [
          ExtractedImage(id: 'p1-0', bytes: Uint8List.fromList([1, 2, 3]), extension: 'png'),
        ],
      );
      final prefixed = prefixImageIds(doc, 'd2-');
      expect(prefixed.text, contains('[[img:d2-p1-0|Bode plot]]'));
      expect(prefixed.images.single.id, 'd2-p1-0');
      final chunks = attachImages(const Chunker().chunk('s', prefixed.text, documentId: 'd2'), prefixed.images);
      expect(chunks.expand((c) => c.images).single.file, 'd2-p1-0.png');
    });

    test('removing a document cleans up its reels and progress', () async {
      final dir = await Directory.systemTemp.createTemp('unrot_svc');
      final services = await AppServices.create(
        directory: dir,
        secrets: MemorySecretStore(),
        speechEngine: SilentSpeechEngine(),
      );
      final c = await services.ingestion.createCollection('Mix');
      await services.ingestion.importText('A', notes('Alpha'), intoSourceId: c.id);
      await services.ingestion.importText('B', notes('Beta'), intoSourceId: c.id);
      final chunks = services.library.chunks(c.id);
      Reel reel(String id, int i) => Reel(
        id: id,
        sourceId: c.id,
        chunkId: chunks[i].id,
        type: 'explainer',
        data: {'body': id},
        createdAt: DateTime(2026),
      );
      services.reels.addAll([reel('ra', 0), reel('rb', 3)]);
      services.progress.reel('ra').views = 1;
      services.progress.reel('rb').views = 1;
      await services.removeDocument(c.id, 'd1');
      expect(services.reels.forSource(c.id).map((r) => r.id), ['rb']);
      expect(services.progress.peekReel('ra'), isNull);
      expect(services.progress.peekReel('rb'), isNotNull);
      expect(services.library.chunks(c.id).every((ch) => ch.documentId == 'd2'), isTrue);
    });
  });

  group('Subject profiles', () {
    test('detects TUM EI subjects from keywords', () {
      const signals =
          'Die Fourier-Transformation eines LTI-Systems: Faltung im Zeitbereich entspricht der Multiplikation im '
          'Frequenzbereich. Die Laplace-Transformation und die z-Transformation verallgemeinern die Fourier-Reihe. '
          'Impulsantwort, Übertragungsfunktion und Abtasttheorem werden behandelt.';
      expect(SubjectProfiles.detect(signals), 'signal_theory');
      const fields =
          'Die Maxwell-Gleichungen beschreiben das elektrische Feld und die magnetische Flussdichte. '
          'Mit dem Gaußschen Satz und dem Durchflutungsgesetz berechnet man Felder; die Maxwell-Gleichungen in '
          'Differentialform, Divergenz und Rotation, Poynting-Vektor, elektrisches Feld einer Punktladung.';
      expect(SubjectProfiles.detect(fields), 'em_field_theory');
      const semi =
          'Im Halbleiter bestimmen Bandlücke, Dotierung und Fermi-Niveau die Ladungsträgerdichte. Der pn-Übergang '
          'bildet eine Raumladungszone; Diffusion und Drift von Elektronen und Löchern im Halbleiter, MOSFET.';
      expect(SubjectProfiles.detect(semi), 'semiconductor_physics');
      expect(SubjectProfiles.detect('Photosynthesis converts light energy into chemical energy in plants.'), 'general');
    });

    test('import detects the subject and profiles add guidance and reel types', () async {
      final env = await Env.create();
      final text =
          '## Zufallsvariablen\n\n${List.filled(4, 'Eine Zufallsvariable hat eine Wahrscheinlichkeitsdichte, einen Erwartungswert und eine Varianz; die Autokorrelation eines stationären Zufallsprozesses und das Leistungsdichtespektrum.').join(' ')}';
      final result = await env.ingestion.importText('Stochastik', text);
      expect(result.source.study.subjectId, 'stochastic_signals');
      final profile = SubjectProfiles.byId('stochastic_signals');
      expect(profile.guidance, isNotEmpty);
      expect(profile.extraMix.keys, contains('calc_exercise'));
      expect(SubjectProfiles.byId('nope').id, 'general');
      // The subject's reel types end up in the sampled mix.
      final types = env.feed.sampleTypes(const ExploreMode(), result.chunks.first.id, 300);
      expect(types.where(mathReelTypes.contains), isNotEmpty);
    });
  });

  group('Math reel types', () {
    test('aliases are normalized', () {
      expect(
        ReelParser.normalizeReel({'type': 'Satz', 'name': 'Rolle', 'statement': 'Es gibt ein xi mit f\'(xi)=0.'})?.$1,
        'theorem',
      );
      expect(
        ReelParser.normalizeReel({
          'type': 'Rechenrezept',
          'title': 'PBZ',
          'steps': [
            {'action': 'a'},
            {'action': 'b'},
          ],
        })?.$1,
        'math_recipe',
      );
      expect(ReelParser.normalizeReel({'type': 'formel', 'name': 'Ohm', 'latex': 'U=RI'})?.$1, 'formula');
      expect(
        ReelParser.normalizeReel({'type': 'calculation', 'problem': 'Compute I', 'answer': '2,5', 'unit': 'A'})?.$1,
        'calc_exercise',
      );
      expect(ReelParser.normalizeReel({'type': 'unknown'}), isNull);
      expect(ReelParser.normalizeReel({'type': 'theorem', 'name': 'x'}), isNull); // no statement
    });

    test('calc exercises parse numbers in many notations', () {
      expect(parseNumber('2,5'), 2.5);
      expect(parseNumber('1.5e-3'), 1.5e-3);
      expect(parseNumber('1,5·10^16'), closeTo(1.5e16, 1e6));
      expect(parseNumber('3 × 10⁻⁵'), closeTo(3e-5, 1e-12));
      expect(parseNumber('2/4'), 0.5);
      expect(parseNumber('abc'), isNull);
      final data = ReelTypes.byId('calc_exercise')!.normalize({
        'problem': 'p',
        'answer': '4,2 V',
        'tolerance': 5,
        'given': [
          {'symbol': 'R', 'value': '2', 'unit': 'Ω'},
        ],
      })!;
      expect(data['answer'], 4.2);
      expect(data['tolerance'], 0.25); // clamped
      expect(calcAnswerCorrect(4.25, 4.2, 0.02), isTrue);
      expect(calcAnswerCorrect(4.5, 4.2, 0.02), isFalse);
      expect(calcAnswerCorrect(0.001, 0, 0.01), isTrue);
    });

    test('math-heavy reels get the neutral background', () {
      Reel r(String type, Map<String, dynamic> data) =>
          Reel(id: 'x', sourceId: 's', chunkId: 'c', type: type, data: data, createdAt: DateTime(2026));
      expect(isMathHeavy(r('theorem', {})), isTrue);
      expect(isMathHeavy(r('calc_exercise', {})), isTrue);
      expect(
        isMathHeavy(
          r('visual', {
            'visual': {'kind': 'function_plot'},
          }),
        ),
        isTrue,
      );
      expect(isMathHeavy(r('explainer', {'body': r'We use $x^2$ and $\int f$.'})), isTrue);
      expect(isMathHeavy(r('explainer', {'body': 'Plants need light.'})), isFalse);
    });
  });

  group('Offline math generators', () {
    final source = StudySource(id: 's', title: 'Analysis', format: 'paste', addedAt: DateTime(2026));
    const text =
        '## Mittelwertsatz\n\n'
        'Satz 3.2 (Mittelwertsatz): Sei f stetig auf [a,b] und differenzierbar auf (a,b). Dann gibt es ein xi mit '
        "f'(xi) = (f(b)-f(a))/(b-a).\n\n"
        'So bestimmt man Extremstellen einer Funktion:\n'
        "1. Bilde die Ableitung f'(x).\n"
        "2. Setze f'(x) = 0 und löse nach x.\n"
        '3. Prüfe das Vorzeichen der zweiten Ableitung.\n\n'
        'Die Funktion wird oft gebraucht und hat viele Anwendungen in der Physik und in der Technik.';

    test('theorem and recipe from a German script', () async {
      final reels = await OfflineReelGenerator().generate(job(source, text, ['theorem', 'math_recipe']));
      final theorem = reels.firstWhere((r) => r.type == 'theorem');
      expect(theorem.str('kind'), 'Satz');
      expect(theorem.str('name'), 'Mittelwertsatz');
      expect(theorem.list('assumptions').first, startsWith('Sei f stetig'));
      final recipe = reels.firstWhere((r) => r.type == 'math_recipe');
      expect((recipe.data['steps'] as List).length, 3);
      expect(recipe.str('goal'), contains('Extremstellen'));
    });

    test('named laws are recognized', () async {
      const law =
          "## Ohm\n\nOhm's law states that the current through a conductor is proportional to the voltage across it. "
          'It is one of the most used relations in circuit analysis and appears in every lab course.';
      final reels = await OfflineReelGenerator().generate(job(source, law, ['theorem']));
      final theorem = reels.firstWhere((r) => r.type == 'theorem');
      expect(theorem.str('kind'), 'Law');
      expect(theorem.str('name'), "Ohm's law");
      expect(theorem.str('statement'), startsWith('the current through a conductor'));
    });

    test('formula card and calculation from a formula with symbols', () async {
      const formula =
          '## Forgetting curve\n\nMemory decays as R(t) = e^(-t/S), where R is the retention, t is the time and S is '
          'the stability of the memory. Reviewing increases the stability so that the curve becomes flatter.';
      final reels = await OfflineReelGenerator().generate(job(source, formula, ['formula', 'calc_exercise']));
      final card = reels.firstWhere((r) => r.type == 'formula');
      expect(card.str('latex'), contains('R(t) = e^{-t/S}'));
      expect((card.data['symbols'] as List).map((s) => (s as Map)['symbol']), containsAll(['R', 't', 'S']));
      final calc = reels.firstWhere((r) => r.type == 'calc_exercise');
      final given = {
        for (final g in calc.data['given'] as List) (g as Map)['symbol']: double.parse(g['value'] as String),
      };
      expect(calc.data['answer'], closeTo(exp(-given['t']! / given['S']!), 1e-9));
    });
  });

  group('Saving AI costs', () {
    test('seen reels come back after the reuse interval instead of new generation', () async {
      final env = await Env.create();
      env.settings.update((s) => s.generation.reelsPerRequest = 3);
      final source = (await env.ingestion.importText('Bio', notes('Cells', sections: 1))).source;
      for (final id in ['a', 'b', 'c']) {
        env.addReel(source, id);
        env.progress.reel(id)
          ..views = 1
          ..lastViewed = env.now.subtract(const Duration(days: 2));
      }
      await env.feed.ensureBuffer(force: true);
      expect(env.feed.items.take(3).map((i) => i.reel.id).toSet(), {'a', 'b', 'c'});
      expect(env.feed.items.take(3).every((i) => i.isRerun), isTrue);
      expect(env.reels.forSource(source.id), hasLength(3)); // nothing generated
    });

    test('recently seen reels are not reused; reuse can be turned off', () async {
      final env = await Env.create();
      env.settings.update((s) => s.generation.reelsPerRequest = 3);
      final source = (await env.ingestion.importText('Bio', notes('Cells', sections: 1))).source;
      env.addReel(source, 'a');
      env.progress.reel('a')
        ..views = 1
        ..lastViewed = env.now.subtract(const Duration(hours: 2));
      await env.feed.ensureBuffer(force: true);
      expect(env.feed.items.first.reel.id, isNot('a'));
      expect(env.reels.forSource(source.id).length, greaterThan(1)); // generated (offline)

      final env2 = await Env.create();
      env2.settings.update((s) {
        s.generation.reelsPerRequest = 3;
        s.feed.reuseReels = false;
      });
      final source2 = (await env2.ingestion.importText('Bio', notes('Cells', sections: 1))).source;
      env2.addReel(source2, 'old');
      env2.progress.reel('old')
        ..views = 1
        ..lastViewed = env2.now.subtract(const Duration(days: 5));
      await env2.feed.ensureBuffer(force: true);
      expect(env2.feed.items.first.isRerun, isFalse);
    });

    test('reels are thrown out after N views, except saved or wrongly answered ones', () async {
      final env = await Env.create();
      final source = (await env.ingestion.importText('Bio', notes('Cells', sections: 1))).source;
      for (final id in ['old', 'saved', 'wrong', 'fresh']) {
        env.addReel(source, id);
      }
      env.progress.reel('old').views = 5;
      env.progress.reel('saved')
        ..views = 9
        ..bookmarked = true;
      env.progress.reel('wrong')
        ..views = 7
        ..lastCorrect = false;
      env.progress.reel('fresh').views = 2;
      Set<String>? retired;
      env.feed.onReelsRetired = (ids) => retired = ids;

      env.settings.update((s) => s.feed.retireAfterViews = 0);
      expect(env.feed.retireExpired(), 0);

      env.settings.update((s) => s.feed.retireAfterViews = 5);
      expect(env.feed.retireExpired(), 1);
      expect(retired, {'old'});
      expect(env.reels.forSource(source.id).map((r) => r.id), unorderedEquals(['saved', 'wrong', 'fresh']));
      expect(env.progress.peekReel('old'), isNull);
      expect(env.progress.stats.reelsRetired, 1);
    });

    test('daily AI request limit falls back to saved/offline reels', () async {
      final env = await Env.create();
      await env.ingestion.importText('Bio', notes('Cells'));
      env.settings.update((s) {
        s.ai.providerId = 'anthropic';
        s.generation.maxAiRequestsPerDay = 2;
      });
      env.progress.stats
        ..countAiRequest(env.now)
        ..countAiRequest(env.now);
      await env.feed.ensureBuffer(force: true);
      expect(env.feed.notice, contains('Daily AI limit'));
      expect(env.feed.lastError, isNull); // the provider was not even called
      expect(env.feed.items, isNotEmpty);
      expect(env.progress.stats.totalAiRequests, 2);
      // A new day resets the budget.
      expect(env.progress.stats.aiRequestsOn(env.now.add(const Duration(days: 1))), 0);
    });

    test('settings for reuse and budget round-trip and clamp', () {
      final s = AppSettings.fromJson({
        'feed': {'reuseAfterHours': 0, 'retireAfterViews': 500, 'reuseReels': false, 'neutralMathBackground': false},
        'generation': {'maxAiRequestsPerDay': -3},
      });
      expect(s.feed.reuseAfterHours, 1);
      expect(s.feed.retireAfterViews, 100);
      expect(s.feed.reuseReels, isFalse);
      expect(s.feed.neutralMathBackground, isFalse);
      expect(s.generation.maxAiRequestsPerDay, 0);
      final d = AppSettings.fromJson({});
      expect(d.feed.reuseAfterHours, 24);
      expect(d.feed.retireAfterViews, 5);
      expect(d.generation.maxAiRequestsPerDay, 40);
    });
  });

  group('Chat subscription exchange', () {
    test('prompt contains sections, formats and the reply shape', () async {
      final env = await Env.create();
      final result = await env.ingestion.importText('Signale', notes('Fourier', sections: 3));
      result.source.study.subjectId = 'signal_theory';
      final mode = env.feed.modes.byId(result.source.study.modeId);
      final types = ReelExchange.typesFor(mode, SubjectProfiles.byId('signal_theory').extraMix, GenerationSettings());
      expect(types, contains('formula'));
      final prompt = const ReelExchange().buildPrompt(
        source: result.source,
        sections: result.chunks.take(2).toList(),
        mode: mode,
        settings: GenerationSettings(),
        types: types,
        reelsPerSection: 4,
      );
      expect(prompt, contains('SECTION 1:'));
      expect(prompt, contains('SECTION 2:'));
      expect(prompt, isNot(contains('SECTION 3:')));
      expect(prompt, contains('"unrot_reels": 1'));
      expect(prompt, contains('create 4 reels'));
      expect(prompt, contains('SUBJECT:'));
      expect(prompt, contains('- formula:'));
      expect(prompt, contains('<<<'));
    });

    test('answers are imported, checked and de-duplicated; export round-trips', () async {
      final env = await Env.create();
      final result = await env.ingestion.importText('Signale', notes('Fourier', sections: 2));
      const answer = '''
Here are your reels!
```json
{"unrot_reels": 1, "reels": [
  {"section": 1, "type": "quiz", "question": "What is F?", "options": ["a","b","c","d"], "answer_index": 2, "explanation": "c"},
  {"section": 2, "type": "Satz", "kind": "Satz", "name": "Faltungssatz", "statement": "Faltung im Zeitbereich ist Multiplikation im Frequenzbereich."},
  {"section": 2, "type": "Satz", "kind": "Satz", "name": "Faltungssatz", "statement": "Faltung im Zeitbereich ist Multiplikation im Frequenzbereich."},
  {"section": 9, "type": "explainer", "title": "x", "body": "y"},
  {"section": 1, "type": "quiz", "question": "broken"}
]}
```''';
      const exchange = ReelExchange();
      final report = exchange.parseAnswer(
        answer,
        source: result.source,
        chunks: result.chunks,
        settings: GenerationSettings(),
      );
      expect(report.reels.map((r) => r.type), ['quiz', 'theorem']);
      expect(report.reels.first.chunkId, result.chunks[0].id);
      expect(report.reels.last.chunkId, result.chunks[1].id);
      expect(report.reels.every((r) => r.generator == 'import:chat'), isTrue);
      expect(report.skipped, 3);
      expect(report.problems.join(' '), contains('Unknown section "9"'));

      env.reels.addAll(report.reels);
      final exported = exchange.exportReels(env.reels.forSource(result.source.id), result.chunks);
      final again = exchange.parseAnswer(
        exported,
        source: result.source,
        chunks: result.chunks,
        settings: GenerationSettings(),
      );
      expect(again.reels.map((r) => r.type), ['quiz', 'theorem']);
      // Importing the same reels again adds nothing.
      final dup = exchange.parseAnswer(
        exported,
        source: result.source,
        chunks: result.chunks,
        settings: GenerationSettings(),
        existing: env.reels.forSource(result.source.id),
      );
      expect(dup.reels, isEmpty);
      expect(dup.skipped, 2);
      expect(
        exchange
            .parseAnswer('no json here', source: result.source, chunks: result.chunks, settings: GenerationSettings())
            .problems,
        isNotEmpty,
      );
    });
  });
}
