import '../../core/models/reel.dart';
import '../../core/models/settings.dart';
import '../ai/ai_provider.dart';
import 'generation_job.dart';
import 'prompt_builder.dart';
import 'reel_parser.dart';

/// Generates reels with a bring-your-own-key AI provider.
class AiReelGenerator implements ReelGenerator {
  AiReelGenerator({
    required this.provider,
    required this.config,
    required this.apiKey,
    required this.maxOutputTokens,
    this.prompts = const PromptBuilder(),
    this.parser = const ReelParser(),
  });

  final AiProvider provider;
  final ProviderConfig config;
  final String? apiKey;
  final int maxOutputTokens;
  final PromptBuilder prompts;
  final ReelParser parser;

  @override
  String get id => '${provider.id}:${config.model.isEmpty ? provider.defaultModel : config.model}';

  @override
  Future<List<Reel>> generate(GenerationJob job) async {
    final request = AiRequest(
      system: prompts.system(job),
      prompt: prompts.user(job),
      jsonSchema: prompts.schema(job),
      maxOutputTokens: maxOutputTokens,
    );
    final response = await provider.complete(request, config, apiKey);
    final reels = parser.parse(response.text, job, generator: '${provider.id}:${response.model}');
    if (reels.isEmpty) {
      throw AiException(
        response.truncated
            ? 'The AI response was cut off. Increase "Max output tokens" in Settings.'
            : 'The AI response could not be turned into reels.',
      );
    }
    return reels;
  }
}
