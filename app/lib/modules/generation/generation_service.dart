import '../../core/storage/settings_repository.dart';
import '../ai/ai_provider.dart';
import '../ai/provider_registry.dart';
import 'ai_reel_generator.dart';
import 'generation_job.dart';
import 'offline_generator.dart';

/// Resolves the active [ReelGenerator] from the current settings.
class GenerationService {
  GenerationService(this.settings, this.providers);

  final SettingsRepository settings;
  final ProviderRegistry providers;
  final OfflineReelGenerator offline = OfflineReelGenerator();

  bool get usesOffline => settings.settings.ai.providerId == offlineProviderId || activeProvider == null;

  AiProvider? get activeProvider => providers.byId(settings.settings.ai.providerId);

  Future<ReelGenerator> current() async {
    final ai = settings.settings.ai;
    final provider = providers.byId(ai.providerId);
    if (provider == null) return offline;
    final apiKey = await settings.readSecret(ProviderRegistry.secretKey(provider.id));
    if (provider.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw AiException(
        'No API key set for ${provider.displayName}. Add one in Settings → AI provider, or switch to Offline.',
      );
    }
    return AiReelGenerator(
      provider: provider,
      config: ai.configFor(provider.id),
      apiKey: apiKey,
      maxOutputTokens: ai.maxOutputTokens,
    );
  }

  /// Sends a tiny request to verify key, model and connectivity.
  Future<String> testConnection() async {
    final ai = settings.settings.ai;
    final provider = providers.byId(ai.providerId);
    if (provider == null) return 'Offline generator — no connection needed.';
    final apiKey = await settings.readSecret(ProviderRegistry.secretKey(provider.id));
    final response = await provider.complete(
      const AiRequest(
        system: 'You are a connection test.',
        prompt: 'Reply with the single word: OK',
        maxOutputTokens: 2000,
      ),
      ai.configFor(provider.id),
      apiKey,
    );
    final reply = response.text.trim();
    return 'Connected to ${response.model}. Reply: "${reply.length > 40 ? '${reply.substring(0, 40)}…' : reply}"';
  }
}
