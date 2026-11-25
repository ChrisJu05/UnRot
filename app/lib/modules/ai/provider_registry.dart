import 'package:http/http.dart' as http;

import 'ai_provider.dart';
import 'providers/anthropic_provider.dart';
import 'providers/gemini_provider.dart';
import 'providers/openai_provider.dart';

/// Id of the built-in, key-less generator (no network).
const offlineProviderId = 'offline';

/// All bring-your-own-key AI backends. Register new providers here.
class ProviderRegistry {
  ProviderRegistry({http.Client? client})
    : providers = [
        AnthropicProvider(client: client),
        OpenAiProvider(client: client),
        GeminiProvider(client: client),
        OpenAiCompatibleProvider(client: client),
      ];

  final List<AiProvider> providers;

  AiProvider? byId(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Key under which the provider's API key is stored in the SecretStore.
  static String secretKey(String providerId) => 'apikey.$providerId';
}
