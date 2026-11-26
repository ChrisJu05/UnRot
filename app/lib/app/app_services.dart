import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/storage/json_store.dart';
import '../core/storage/repositories.dart';
import '../core/storage/secret_store.dart';
import '../core/storage/settings_repository.dart';
import '../modules/ai/provider_registry.dart';
import '../modules/feed/feed_engine.dart';
import '../modules/generation/generation_service.dart';
import '../modules/ingestion/ingestion_service.dart';
import '../modules/speech/speech_controller.dart';
import '../modules/speech/speech_engine.dart';
import '../modules/study/modes/builtin_modes.dart';
import '../modules/study/progress_tracker.dart';
import '../modules/study/study_mode.dart';

/// Composition root: creates and wires every service of the app.
///
/// Swap implementations here (e.g. a keychain-backed [SecretStore] or a
/// database-backed store) without touching the UI.
class AppServices {
  AppServices._({
    required this.dataDirectory,
    required this.store,
    required this.settings,
    required this.library,
    required this.reels,
    required this.progress,
    required this.annotations,
    required this.providers,
    required this.generation,
    required this.ingestion,
    required this.modes,
    required this.tracker,
    required this.feed,
    required this.speech,
  });

  final Directory dataDirectory;
  final JsonStore store;
  final SettingsRepository settings;
  final LibraryRepository library;
  final ReelRepository reels;
  final ProgressRepository progress;
  final AnnotationRepository annotations;
  final ProviderRegistry providers;
  final GenerationService generation;
  final IngestionService ingestion;
  final StudyModes modes;
  final ProgressTracker tracker;
  final FeedEngine feed;
  final SpeechController speech;

  static Future<Directory> defaultDataDirectory() async {
    final override = Platform.environment['UNROT_DATA_DIR'];
    if (override != null && override.isNotEmpty) return Directory(override);
    final base = await getApplicationSupportDirectory();
    return Directory(base.path);
  }

  static Future<AppServices> create({Directory? directory, SecretStore? secrets, SpeechEngine? speechEngine}) async {
    final dir = directory ?? await defaultDataDirectory();
    await dir.create(recursive: true);
    final store = JsonStore(dir);
    final settings = SettingsRepository(store, secrets ?? FileSecretStore(dir));
    final library = LibraryRepository(store);
    final reels = ReelRepository(store);
    final progress = ProgressRepository(store);
    final annotations = AnnotationRepository(store);
    await settings.load();
    await library.load();
    await reels.load(library.sources.map((s) => s.id));
    await progress.load();
    await annotations.load();

    final providers = ProviderRegistry();
    final generation = GenerationService(settings, providers);
    final ingestion = IngestionService(library, allowPdfSystemFallback: settings.settings.usePdftotext);
    final modes = StudyModes(builtinStudyModes());
    final tracker = ProgressTracker(progress);
    final feed = FeedEngine(
      library: library,
      reels: reels,
      progress: progress,
      settings: settings,
      generation: generation,
      modes: modes,
      tracker: tracker,
    );
    feed.onReelsRetired = (ids) => annotations.removeWhere((key) => ids.contains(key.split('#').first));
    feed.retireExpired();
    final speech = SpeechController(
      speechEngine ?? SpeechEngine.forPlatform(),
      settings: () => settings.settings.audio,
    );
    return AppServices._(
      dataDirectory: dir,
      store: store,
      settings: settings,
      library: library,
      reels: reels,
      progress: progress,
      annotations: annotations,
      providers: providers,
      generation: generation,
      ingestion: ingestion,
      modes: modes,
      tracker: tracker,
      feed: feed,
      speech: speech,
    );
  }

  /// Deletes a source with all its reels, progress and annotations.
  Future<void> deleteSource(String sourceId) async {
    final reelIds = reels.forSource(sourceId).map((r) => r.id).toSet();
    feed.removeSource(sourceId);
    progress.removeSource(sourceId, reelIds);
    annotations.removeWhere((key) => reelIds.contains(key.split('#').first));
    await reels.removeSource(sourceId);
    if (settings.settings.feed.focusSourceId == sourceId) {
      settings.update((s) => s.feed.focusSourceId = null);
    }
    await library.removeSource(sourceId);
  }

  /// Removes one document of a collection with its sections, reels, progress and figures.
  Future<void> removeDocument(String sourceId, String documentId) async {
    final removed = await library.removeDocument(sourceId, documentId);
    final chunkIds = removed.map((c) => c.id).toSet();
    final reelIds = reels.all.where((r) => chunkIds.contains(r.chunkId)).map((r) => r.id).toSet();
    feed.removeChunks(chunkIds);
    progress.removeChunks(chunkIds, reelIds);
    annotations.removeWhere((key) => reelIds.contains(key.split('#').first));
    reels.removeIds(reelIds);
  }

  /// File of a figure extracted from a source (used by visual reels).
  File? sourceImage(String sourceId, String imageId) => library.imageFile(sourceId, imageId);

  Future<void> flush() => store.flush();
}
