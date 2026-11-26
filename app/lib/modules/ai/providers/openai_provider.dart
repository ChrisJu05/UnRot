import '../../../core/models/settings.dart';
import '../../../core/util/json.dart';
import '../ai_provider.dart';

/// OpenAI Chat Completions API. Also the base for any OpenAI-compatible server.
class OpenAiProvider extends HttpAiProvider {
  OpenAiProvider({super.client});

  @override
  String get id => 'openai';
  @override
  String get displayName => 'OpenAI';
  @override
  String get description => 'GPT models via the OpenAI API.';
  @override
  bool get requiresApiKey => true;
  @override
  bool get supportsBaseUrl => false;
  @override
  String get defaultModel => 'gpt-5-mini';
  @override
  String get defaultBaseUrl => 'https://api.openai.com/v1';
  @override
  List<String> get suggestedModels => const ['gpt-5-mini', 'gpt-5', 'gpt-4.1-mini'];
  @override
  String get apiKeyHelp =>
      'Create a key at platform.openai.com → API keys. (ChatGPT subscriptions do not include API keys.)';

  /// Official OpenAI uses `max_completion_tokens`; many compatible servers only know `max_tokens`.
  bool get useMaxCompletionTokens => true;

  bool jsonMode(ProviderConfig config) => (config.options['jsonMode'] ?? 'on') == 'on';

  Map<String, String> headers(String? apiKey) => {
    if (apiKey != null && apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
  };

  @override
  Future<AiResponse> complete(AiRequest request, ProviderConfig config, String? apiKey) async {
    if (requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw AiException('No API key configured for $displayName.');
    }
    final modelId = model(config);
    final body = <String, Object?>{
      'model': modelId,
      'messages': [
        {'role': 'system', 'content': request.system},
        {'role': 'user', 'content': request.prompt},
      ],
      if (useMaxCompletionTokens)
        'max_completion_tokens': request.maxOutputTokens
      else
        'max_tokens': request.maxOutputTokens,
      if (request.wantsJson && jsonMode(config)) 'response_format': {'type': 'json_object'},
    };
    Map<String, dynamic> json;
    try {
      json = await postJson(Uri.parse('${baseUrl(config)}/chat/completions'), headers(apiKey), body);
    } on AiException catch (e) {
      // Retry without JSON mode for servers that don't support response_format.
      if (e.statusCode == 400 && body.containsKey('response_format')) {
        body.remove('response_format');
        json = await postJson(Uri.parse('${baseUrl(config)}/chat/completions'), headers(apiKey), body);
      } else {
        rethrow;
      }
    }
    final choices = json['choices'] is List ? json['choices'] as List : const [];
    if (choices.isEmpty) throw AiException('The model returned no answer.');
    final choice = jMap(choices.first);
    final message = jMap(choice['message']);
    final refusal = jStringOrNull(message['refusal']);
    if (refusal != null) throw AiException('The model declined: $refusal');
    final usage = jMap(json['usage']);
    return AiResponse(
      text: _content(message['content']),
      model: jString(json['model'], modelId),
      inputTokens: usage['prompt_tokens'] is int ? usage['prompt_tokens'] as int : null,
      outputTokens: usage['completion_tokens'] is int ? usage['completion_tokens'] as int : null,
      truncated: choice['finish_reason'] == 'length',
    );
  }

  static String _content(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content.whereType<Map>().map((p) => jString(p['text'])).join();
    }
    return '';
  }

  @override
  Future<List<String>> listModels(ProviderConfig config, String? apiKey) async {
    final json = await getJson(Uri.parse('${baseUrl(config)}/models'), headers(apiKey));
    final data = json['data'] is List
        ? json['data'] as List
        : (json['models'] is List ? json['models'] as List : const []);
    final ids = data.whereType<Map>().map((m) => jString(m['id'] ?? m['name'])).where((id) => id.isNotEmpty).toList();
    if (id == 'openai') {
      ids.removeWhere(
        (m) => RegExp(
          r'embedding|whisper|tts|dall-e|moderation|image|audio|realtime|transcribe|search',
          caseSensitive: false,
        ).hasMatch(m),
      );
    }
    ids.sort();
    return ids;
  }
}

/// Any server that speaks the OpenAI Chat Completions protocol: OpenRouter,
/// Ollama, LM Studio, Groq, Mistral, DeepSeek, vLLM, LocalAI, ...
class OpenAiCompatibleProvider extends OpenAiProvider {
  OpenAiCompatibleProvider({super.client});

  static const presets = <String, String>{
    'OpenRouter': 'https://openrouter.ai/api/v1',
    'Ollama (local)': 'http://localhost:11434/v1',
    'LM Studio (local)': 'http://localhost:1234/v1',
    'Groq': 'https://api.groq.com/openai/v1',
    'Mistral': 'https://api.mistral.ai/v1',
    'DeepSeek': 'https://api.deepseek.com/v1',
  };

  @override
  String get id => 'openai_compatible';
  @override
  String get displayName => 'OpenAI-compatible';
  @override
  String get description => 'OpenRouter, Ollama, LM Studio, Groq, Mistral and other compatible servers.';
  @override
  bool get requiresApiKey => false;
  @override
  bool get supportsBaseUrl => true;
  @override
  String get defaultModel => 'llama3.2';
  @override
  String get defaultBaseUrl => 'http://localhost:11434/v1';
  @override
  List<String> get suggestedModels => const [];
  @override
  String get apiKeyHelp => 'Optional for local servers (Ollama, LM Studio). Use the key from your provider otherwise.';
  @override
  bool get useMaxCompletionTokens => false;
  @override
  bool jsonMode(ProviderConfig config) => (config.options['jsonMode'] ?? 'on') == 'on';
  @override
  List<ProviderOption> get options => const [
    ProviderOption(
      key: 'jsonMode',
      label: 'JSON mode',
      help: 'Ask the server for JSON output (turn off if your server rejects response_format).',
      choices: {'on': 'On', 'off': 'Off'},
      defaultValue: 'on',
    ),
  ];
}
