import '../../../core/models/settings.dart';
import '../../../core/util/json.dart';
import '../ai_provider.dart';

/// Anthropic Claude via the Messages API (raw HTTP; there is no official Dart SDK).
class AnthropicProvider extends HttpAiProvider {
  AnthropicProvider({super.client});

  static const apiVersion = '2026-10-21';

  /// Models that accept the server-side refusal fallback parameter.
  static final _fallbackModels = RegExp(r'^claude-(fable-5-[12]|opus-5-5|opus-5$|sonnet-5-5)');

  /// Models that accept `output_config.effort`.
  static final _effortModels = RegExp(r'^claude-(fable|mythos|opus-5|sonnet-5|haiku-5|opus-4-[5-8]|sonnet-4-6)');

  @override
  String get id => 'anthropic';
  @override
  String get displayName => 'Anthropic Claude';
  @override
  String get description => 'Claude models via the Anthropic API.';
  @override
  bool get requiresApiKey => true;
  @override
  bool get supportsBaseUrl => true;
  @override
  String get defaultModel => 'claude-opus-5-5';
  @override
  String get defaultBaseUrl => 'https://api.anthropic.com';
  @override
  List<String> get suggestedModels => const [
    'claude-opus-5-5',
    'claude-sonnet-5-5',
    'claude-haiku-5-5',
    'claude-fable-5-2',
  ];
  @override
  String get apiKeyHelp =>
      'Create a key at platform.claude.com → API keys. (Claude.ai subscriptions do not include API keys.)';
  @override
  List<ProviderOption> get options => const [
    ProviderOption(
      key: 'effort',
      label: 'Reasoning effort',
      help: 'Lower = faster and cheaper reels; higher = more careful content.',
      choices: {'': 'Model default', 'low': 'Low', 'medium': 'Medium', 'high': 'High'},
    ),
  ];

  Map<String, String> _headers(String? apiKey) => {'x-api-key': apiKey ?? '', 'anthropic-version': apiVersion};

  @override
  Future<AiResponse> complete(AiRequest request, ProviderConfig config, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) throw AiException('No Anthropic API key configured.');
    final modelId = model(config);
    try {
      return await _send(request, config, apiKey, modelId, useSchema: request.jsonSchema != null, allowFallback: true);
    } on AiException catch (e) {
      // Some models, organisations or proxies reject structured outputs or the
      // fallback parameter: retry once with the plain request.
      if (e.statusCode == 400) {
        return _send(request, config, apiKey, modelId, useSchema: false, allowFallback: false);
      }
      rethrow;
    }
  }

  Future<AiResponse> _send(
    AiRequest request,
    ProviderConfig config,
    String apiKey,
    String modelId, {
    required bool useSchema,
    required bool allowFallback,
  }) async {
    final effort = config.options['effort'] ?? '';
    final outputConfig = <String, Object?>{
      if (effort.isNotEmpty && _effortModels.hasMatch(modelId)) 'effort': effort,
      if (useSchema) 'format': {'type': 'json_schema', 'schema': request.jsonSchema},
    };
    final fallback = allowFallback && _fallbackModels.hasMatch(modelId);
    final body = <String, Object?>{
      'model': modelId,
      'max_tokens': request.maxOutputTokens,
      'system': request.system,
      'messages': [
        {'role': 'user', 'content': request.prompt},
      ],
      if (outputConfig.isNotEmpty) 'output_config': outputConfig,
      // On a safety refusal, let the API retry on a fallback model automatically.
      if (fallback) 'fallbacks': 'default',
    };
    final headers = {..._headers(apiKey), if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01'};
    final json = await postJson(Uri.parse('${baseUrl(config)}/v1/messages'), headers, body);
    final stopReason = jString(json['stop_reason']);
    if (stopReason == 'refusal') {
      throw AiException('Claude declined to generate content for this section.');
    }
    final content = json['content'] is List ? json['content'] as List : const [];
    final text = content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => jString(b['text'])).join();
    final usage = jMap(json['usage']);
    return AiResponse(
      text: text,
      model: jString(json['model'], modelId),
      inputTokens: usage['input_tokens'] is int ? usage['input_tokens'] as int : null,
      outputTokens: usage['output_tokens'] is int ? usage['output_tokens'] as int : null,
      truncated: stopReason == 'max_tokens',
    );
  }

  @override
  Future<List<String>> listModels(ProviderConfig config, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) throw AiException('Enter an API key first.');
    final ids = <String>[];
    String? after;
    for (var page = 0; page < 5; page++) {
      final uri = Uri.parse('${baseUrl(config)}/v1/models')
          .replace(queryParameters: {'limit': '100', 'after_id': ?after});
      final json = await getJson(uri, _headers(apiKey));
      final data = json['data'] is List ? json['data'] as List : const [];
      ids.addAll(data.whereType<Map>().map((m) => jString(m['id'])).where((id) => id.isNotEmpty));
      if (json['has_more'] != true) break;
      after = jStringOrNull(json['last_id']);
      if (after == null) break;
    }
    return ids;
  }
}
