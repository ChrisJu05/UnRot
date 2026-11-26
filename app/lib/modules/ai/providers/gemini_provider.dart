import '../../../core/models/settings.dart';
import '../../../core/util/json.dart';
import '../ai_provider.dart';

/// Google Gemini via the Generative Language API.
class GeminiProvider extends HttpAiProvider {
  GeminiProvider({super.client});

  @override
  String get id => 'gemini';
  @override
  String get displayName => 'Google Gemini';
  @override
  String get description => 'Gemini models via Google AI Studio API keys.';
  @override
  bool get requiresApiKey => true;
  @override
  bool get supportsBaseUrl => false;
  @override
  String get defaultModel => 'gemini-flash-latest';
  @override
  String get defaultBaseUrl => 'https://generativelanguage.googleapis.com/v1beta';
  @override
  List<String> get suggestedModels => const ['gemini-flash-latest', 'gemini-pro-latest'];
  @override
  String get apiKeyHelp => 'Create a key at aistudio.google.com → Get API key.';

  @override
  Future<AiResponse> complete(AiRequest request, ProviderConfig config, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) throw AiException('No Gemini API key configured.');
    final modelId = model(config).replaceFirst('models/', '');
    final body = <String, Object?>{
      'systemInstruction': {
        'parts': [
          {'text': request.system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': request.prompt},
          ],
        },
      ],
      'generationConfig': {
        'maxOutputTokens': request.maxOutputTokens,
        if (request.wantsJson) 'responseMimeType': 'application/json',
      },
    };
    final json = await postJson(Uri.parse('${baseUrl(config)}/models/$modelId:generateContent'), {
      'x-goog-api-key': apiKey,
    }, body);
    final candidates = json['candidates'] is List ? json['candidates'] as List : const [];
    if (candidates.isEmpty) {
      final reason = jString(jMap(json['promptFeedback'])['blockReason']);
      throw AiException(reason.isEmpty ? 'Gemini returned no answer.' : 'Gemini blocked the request ($reason).');
    }
    final candidate = jMap(candidates.first);
    final finish = jString(candidate['finishReason']);
    if (finish == 'SAFETY' || finish == 'RECITATION' || finish == 'PROHIBITED_CONTENT') {
      throw AiException('Gemini stopped generating ($finish).');
    }
    final parts = jMap(candidate['content'])['parts'];
    final text = (parts is List ? parts : const [])
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => jString(p['text']))
        .join();
    final usage = jMap(json['usageMetadata']);
    return AiResponse(
      text: text,
      model: modelId,
      inputTokens: usage['promptTokenCount'] is int ? usage['promptTokenCount'] as int : null,
      outputTokens: usage['candidatesTokenCount'] is int ? usage['candidatesTokenCount'] as int : null,
      truncated: finish == 'MAX_TOKENS',
    );
  }

  @override
  Future<List<String>> listModels(ProviderConfig config, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) throw AiException('Enter an API key first.');
    final json = await getJson(Uri.parse('${baseUrl(config)}/models?pageSize=200'), {'x-goog-api-key': apiKey});
    final models = json['models'] is List ? json['models'] as List : const [];
    return models
        .whereType<Map>()
        .where((m) => jStringList(m['supportedGenerationMethods']).contains('generateContent'))
        .map((m) => jString(m['name']).replaceFirst('models/', ''))
        .where((id) => id.isNotEmpty)
        .toList()
      ..sort();
  }
}
