import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unrot/core/models/progress.dart';
import 'package:unrot/core/models/reel.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/core/models/source.dart';
import 'package:unrot/core/storage/json_store.dart';
import 'package:unrot/core/storage/repositories.dart';
import 'package:unrot/core/storage/secret_store.dart';
import 'package:unrot/core/storage/settings_repository.dart';
import 'package:unrot/modules/ai/provider_registry.dart';
import 'package:unrot/modules/feed/feed_engine.dart';
import 'package:unrot/modules/generation/generation_service.dart';
import 'package:unrot/modules/ingestion/ingestion_service.dart';
import 'package:unrot/modules/study/modes/builtin_modes.dart';
import 'package:unrot/modules/study/progress_tracker.dart';
import 'package:unrot/modules/study/study_mode.dart';

String section(String title, String topic) =>
    '## $title\n\n${List.generate(8, (i) => '$topic fact number $i explains an important detail about $topic.').join(' ')}';

class Harness {
  Harness._(
    this.dir,
    this.store,
    this.settings,
    this.library,
    this.reels,
    this.progress,
    this.tracker,
    this.feed,
    this.ingestion,
  );

  final Directory dir;
  final JsonStore store;
  final SettingsRepository settings;
  final LibraryRepository library;
  final ReelRepository reels;
  final ProgressRepository progress;
  final ProgressTracker tracker;
  final FeedEngine feed;
  final IngestionService ingestion;
  DateTime now = DateTime(2026, 11, 25, 10);

  static Future<Harness> create() async {
    final dir = await Directory.systemTemp.createTemp('unrot_test');
    final store = JsonStore(dir);
    final settings = SettingsRepository(store, MemorySecretStore());
    final library = LibraryRepository(store);
    final reels = ReelRepository(store);
    final progress = ProgressRepository(store);
    final tracker = ProgressTracker(progress);
    late Harness h;
    final feed = FeedEngine(
      library: library,
      reels: reels,
      progress: progress,
      settings: settings,
      generation: GenerationService(settings, ProviderRegistry()),
      modes: StudyModes(builtinStudyModes()),
      tracker: tracker,
      random: Random(1),
      clock: () => h.now,
    );
    h = Harness._(dir, store, settings, library, reels, progress, tracker, feed, IngestionService(library));
    return h;
  }

  Future<StudySource> addSource(String title, {String mode = 'linear', int sections = 4}) async {
    final text = List.generate(sections, (i) => section('$title part ${i + 1}', '$title topic ${i + 1}')).join('\n\n');
    final result = await ingestion.importText(title, text, study: SourceStudySettings(modeId: mode));
    return result.source;
  }
}

void main() {
  group('SpacedRepetition', () {
    test('intervals grow with good answers and reset on again', () {
      final now = DateTime(2026);
      final s = ReelState(reelId: 'r');
      SpacedRepetition.schedule(s, RecallRating.good, now);
      expect(s.intervalDays, 1);
      SpacedRepetition.schedule(s, RecallRating.good, now);
      expect(s.intervalDays, 3);
      SpacedRepetition.schedule(s, RecallRating.good, now);
      expect(s.intervalDays, closeTo(7.5, 0.01));
      expect(s.due, now.add(const Duration(hours: 180)));
      SpacedRepetition.schedule(s, RecallRating.again, now);
      expect(s.repetitions, 0);
      expect(s.lapses, 1);
      expect(s.due, now.add(const Duration(minutes: 10)));
      expect(s.ease, closeTo(2.3, 0.001));
    });
  });

  group('ProgressTracker', () {
    test('views, answers and feedback update mastery and stats', () async {
      final h = await Harness.create();
      final reel = Reel(
        id: 'r1',
        sourceId: 's',
        chunkId: 's:0',
        type: 'quiz',
        data: {'question': 'Q?'},
        createdAt: h.now,
      );
      h.tracker.recordView(reel, h.now);
      h.tracker.recordView(reel, h.now);
      final cp = h.progress.peekChunk('s:0')!;
      expect(cp.reelsSeen, 1);
      expect(h.progress.stats.totalReels, 2);
      h.tracker.recordAnswer(reel, false, h.now);
      expect(cp.incorrect, 1);
      expect(cp.missedPrompts, ['Q?']);
      expect(h.progress.peekReel('r1')!.isDue(h.now.add(const Duration(minutes: 11))), isTrue);
      final before = cp.mastery;
      h.tracker.recordAnswer(reel, true, h.now);
      expect(cp.mastery, greaterThan(before));
      h.tracker.recordFeedback(reel, ReelFeedback.confusing);
      expect(cp.difficultyBias, -1);
      expect(cp.confusingTopics, ['Q?']);
      expect(h.progress.stats.streak(h.now), 1);
    });
  });

  group('Study modes', () {
    test('linear mode advances only after a section is learned', () async {
      final h = await Harness.create();
      final source = await h.addSource('Bio');
      const mode = LinearMode();
      final chunks = h.library.chunks(source.id);
      expect(mode.nextChunk(h.feed.contextFor(source))!.id, chunks[0].id);
      h.progress.chunk(chunks[0].id, source.id)
        ..reelsSeen = 5
        ..mastery = 0.7;
      expect(mode.nextChunk(h.feed.contextFor(source))!.id, chunks[1].id);
      expect(mode.completion(h.feed.contextFor(source)), closeTo(1 / chunks.length, 0.001));
    });

    test('exam mode drills weak sections and paces by exam date', () async {
      final h = await Harness.create();
      final source = await h.addSource('Law', mode: 'exam', sections: 6);
      source.study.examDate = h.now.add(const Duration(days: 3));
      final chunks = h.library.chunks(source.id);
      h.progress.chunk(chunks[0].id, source.id)
        ..reelsSeen = 6
        ..mastery = 0.2;
      final ctx = h.feed.contextFor(source);
      expect(ExamPrepMode.daysLeft(ctx), 3);
      expect(ExamPrepMode.requiredPace(ctx, const ExamPrepMode()), 2);
      final picks = List.generate(40, (_) => const ExamPrepMode().nextChunk(ctx)!.id);
      expect(picks, contains(chunks[0].id)); // weak spot
      expect(picks, contains(chunks[1].id)); // new material
    });

    test('rote mode pauses new material when too many reviews are due', () async {
      final h = await Harness.create();
      final source = await h.addSource('Vocab', mode: 'rote');
      final chunk = h.library.chunks(source.id).first;
      h.reels.addAll([
        for (var i = 0; i < 30; i++)
          Reel(
            id: 'r$i',
            sourceId: source.id,
            chunkId: chunk.id,
            type: 'flashcard',
            data: {'front': 'f$i', 'back': 'b'},
            createdAt: h.now,
          ),
      ]);
      for (var i = 0; i < 30; i++) {
        h.progress.reel('r$i').due = h.now.subtract(const Duration(hours: 1));
      }
      expect(const RoteMode().nextChunk(h.feed.contextFor(source)), isNull);
    });
  });

  group('FeedEngine', () {
    test('builds a feed from the offline generator, teaching first, without duplicates', () async {
      final h = await Harness.create();
      await h.addSource('Bio');
      await h.feed.ensureBuffer(force: true);
      expect(h.feed.items, isNotEmpty);
      expect(h.feed.items.first.reel.type, anyOf('explainer', 'key_points', 'mnemonic'));
      final ids = h.feed.items.map((i) => i.reel.id).toList();
      expect(ids.toSet().length, ids.length);
      // First visible reel is counted as viewed.
      expect(h.progress.peekReel(ids.first)!.views, 1);
      // Scrolling to the end triggers more generation.
      final initial = h.feed.items.length;
      for (var i = 1; i < initial + 2 && i < h.feed.items.length; i++) {
        h.feed.onPageChanged(i);
        await h.feed.ensureBuffer();
      }
      final all = h.feed.items.map((i) => i.reel.id).toList();
      expect(all.length, greaterThan(ids.length));
      expect(all.toSet().length, all.length);
    });

    test('respects feed shares, hidden sources and focus', () async {
      final h = await Harness.create();
      final a = await h.addSource('Alpha');
      final b = await h.addSource('Beta');
      a.study.feedWeight = 3;
      b.study.feedWeight = 1;
      expect(h.feed.sourceShares()[a.id], closeTo(0.75, 0.001));
      b.study.includeInFeed = false;
      expect(h.feed.activeSources.map((s) => s.id), [a.id]);
      h.settings.update((s) => s.feed.focusSourceId = b.id);
      expect(h.feed.activeSources.map((s) => s.id), [b.id]);
      h.settings.update((s) => s.feed.focusSourceId = null);
      final chunk = h.library.chunks(b.id)[2];
      await h.feed.setFocusChunk(chunk.id);
      expect(h.feed.items.every((i) => i.reel.chunkId == chunk.id), isTrue);
    });

    test('mixes due reviews into the feed', () async {
      final h = await Harness.create();
      await h.addSource('Bio');
      await h.feed.ensureBuffer(force: true);
      final quiz = h.feed.items[1].reel;
      h.tracker.recordAnswer(quiz, false, h.now);
      h.now = h.now.add(const Duration(hours: 1));
      h.settings.update((s) => s.feed.reviewShare = 0.8);
      await h.feed.refresh();
      expect(h.feed.items.skip(1).any((i) => i.isReview && i.reel.id == quiz.id), isTrue);
    });

    test('cached reels are only re-used in the chosen language', () async {
      final h = await Harness.create();
      final source = await h.addSource('Bio');
      final chunk = h.library.chunks(source.id).first;
      h.reels.addAll([
        Reel(
          id: 'de1',
          sourceId: source.id,
          chunkId: chunk.id,
          type: 'explainer',
          data: {'body': 'Deutsch'},
          createdAt: h.now,
          language: 'Deutsch',
        ),
        Reel(
          id: 'en1',
          sourceId: source.id,
          chunkId: chunk.id,
          type: 'explainer',
          data: {'body': 'English'},
          createdAt: h.now,
          language: 'English',
        ),
      ]);
      source.study.reelLanguage = 'English';
      await h.feed.ensureBuffer(force: true);
      final ids = h.feed.items.map((i) => i.reel.id).toList();
      expect(ids, contains('en1'));
      expect(ids, isNot(contains('de1')));
      expect(h.feed.items.where((i) => i.reel.language != null).every((i) => i.reel.language == 'English'), isTrue);
    });

    test('visual level controls how often visual reels are requested', () async {
      final h = await Harness.create();
      await h.addSource('Bio');
      const mode = ExploreMode();
      h.settings.update((s) => s.generation.visualLevel = 'off');
      expect(h.feed.sampleTypes(mode, 'x:0', 200), isNot(contains('visual')));
      h.settings.update((s) => s.generation.visualLevel = 'lots');
      expect(h.feed.sampleTypes(mode, 'x:0', 200).where((t) => t == 'visual').length, greaterThan(40));
    });

    test('reports an empty library and an AI provider without key', () async {
      final h = await Harness.create();
      await h.feed.ensureBuffer(force: true);
      expect(h.feed.emptyReason, 'no_sources');
      await h.addSource('Bio');
      h.settings.update((s) {
        s.ai.providerId = 'anthropic';
        s.generation.fallbackToOffline = false;
      });
      await h.feed.ensureBuffer(force: true);
      expect(h.feed.lastError, contains('No API key'));
      h.settings.update((s) => s.generation.fallbackToOffline = true);
      await h.feed.retry();
      expect(h.feed.items, isNotEmpty);
    });
  });

  group('Persistence', () {
    test('everything survives a restart', () async {
      final h = await Harness.create();
      final source = await h.addSource('Bio');
      await h.feed.ensureBuffer(force: true);
      h.settings.update((s) {
        s.generation.style = 'playful';
        s.ai.configFor('anthropic').model = 'claude-sonnet-5-5';
      });
      await h.store.flush();

      final store = JsonStore(h.dir);
      final library = LibraryRepository(store);
      await library.load();
      final reels = ReelRepository(store);
      await reels.load(library.sources.map((s) => s.id));
      final progress = ProgressRepository(store);
      await progress.load();
      final settings = SettingsRepository(store, MemorySecretStore());
      await settings.load();
      expect(library.sources.single.id, source.id);
      expect(library.chunks(source.id).length, h.library.chunks(source.id).length);
      expect(reels.count, h.reels.count);
      expect(progress.stats.totalReels, h.progress.stats.totalReels);
      expect(settings.settings.generation.style, 'playful');
      expect(settings.settings.ai.configFor('anthropic').model, 'claude-sonnet-5-5');
    });

    test('file secret store keeps keys out of settings and private', () async {
      final dir = await Directory.systemTemp.createTemp('unrot_secret');
      final secrets = FileSecretStore(dir);
      await secrets.write('apikey.anthropic', 'sk-ant-xyz');
      expect(await FileSecretStore(dir).read('apikey.anthropic'), 'sk-ant-xyz');
      if (Platform.isLinux || Platform.isMacOS) {
        final mode = (await File('${dir.path}/secrets.json').stat()).mode & 0x1ff;
        expect(mode, 0x180); // 0600
      }
      expect(AppSettings().toJson().toString(), isNot(contains('sk-ant')));
    });
  });
}
