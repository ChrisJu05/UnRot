import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unrot/core/models/settings.dart';
import 'package:unrot/modules/ai/ai_provider.dart';
import 'package:unrot/modules/ai/providers/anthropic_provider.dart';
import 'package:unrot/modules/ai/providers/gemini_provider.dart';
import 'package:unrot/modules/ai/providers/openai_provider.dart';

const request = AiRequest(
  system: 'sys',
  prompt: 'make reels',
  jsonSchema: {'type': 'object', 'properties': {}, 'required': [], 'additionalProperties': false},
  maxOutputTokens: 1234,
);

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('Anthropic', () {
    test('sends a Messages API request with structured output and parses text blocks', () async {
      late http.Request captured;
      final provider = AnthropicProvider(
        client: MockClient((req) async {
          captured = req;
          return jsonResponse({
            'model': 'claude-opus-5-5',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': '{"reels":'},
              {'type': 'text', 'text': '[]}'},
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          });
        }),
      );
      final config = ProviderConfig(options: {'effort': 'low'});
      final res = await provider.complete(request, config, 'sk-ant-test');
      expect(res.text, '{"reels":[]}');
      expect(res.outputTokens, 5);
      expect(captured.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(captured.headers['x-api-key'], 'sk-ant-test');
      expect(captured.headers['anthropic-version'], AnthropicProvider.apiVersion);
      expect(captured.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['max_tokens'], 1234);
      expect(body['system'], 'sys');
      expect(body['fallbacks'], 'default');
      expect(body['output_config']['effort'], 'low');
      expect(body['output_config']['format']['type'], 'json_schema');
      expect(body.containsKey('temperature'), isFalse);
    });

    test('refusal becomes an error; 400 retries once without schema and fallbacks', () async {
      var calls = 0;
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        client: MockClient((req) async {
          calls++;
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (calls == 1) {
            return jsonResponse({
              'type': 'error',
              'error': {'message': 'output_config not supported'},
            }, 400);
          }
          return jsonResponse({'stop_reason': 'refusal', 'content': []});
        }),
      );
      await expectLater(
        provider.complete(request, ProviderConfig(model: 'claude-haiku-5-5'), 'k'),
        throwsA(isA<AiException>()),
      );
      expect(calls, 2);
      expect(bodies.last.containsKey('output_config'), isFalse);
      expect(bodies.first.containsKey('fallbacks'), isFalse); // haiku has no server-side fallback
    });

    test('missing key and auth errors are reported clearly', () async {
      final provider = AnthropicProvider(
        client: MockClient(
          (_) async => jsonResponse({
            'error': {'message': 'invalid x-api-key'},
          }, 401),
        ),
      );
      await expectLater(provider.complete(request, ProviderConfig(), null), throwsA(isA<AiException>()));
      try {
        await provider.complete(request, ProviderConfig(), 'bad');
        fail('should throw');
      } on AiException catch (e) {
        expect(e.statusCode, 401);
        expect(e.message, contains('API key'));
      }
    });

    test('lists models with pagination', () async {
      final provider = AnthropicProvider(
        client: MockClient((req) async {
          final after = req.url.queryParameters['after_id'];
          return after == null
              ? jsonResponse({
                  'data': [
                    {'id': 'claude-opus-5-5'},
                  ],
                  'has_more': true,
                  'last_id': 'claude-opus-5-5',
                })
              : jsonResponse({
                  'data': [
                    {'id': 'claude-haiku-5-5'},
                  ],
                  'has_more': false,
                });
        }),
      );
      expect(await provider.listModels(ProviderConfig(), 'k'), ['claude-opus-5-5', 'claude-haiku-5-5']);
    });
  });

  group('OpenAI', () {
    test('chat completions with JSON mode and max_completion_tokens', () async {
      late http.Request captured;
      final provider = OpenAiProvider(
        client: MockClient((req) async {
          captured = req;
          return jsonResponse({
            'model': 'gpt-5-mini',
            'choices': [
              {
                'message': {'content': '{"reels":[]}'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 3, 'completion_tokens': 4},
          });
        }),
      );
      final res = await provider.complete(request, ProviderConfig(), 'sk-test');
      expect(res.text, '{"reels":[]}');
      expect(captured.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(captured.headers['authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['max_completion_tokens'], 1234);
      expect(body['response_format'], {'type': 'json_object'});
      expect((body['messages'] as List).first['role'], 'system');
    });

    test('compatible server: custom base URL, max_tokens, no auth without key', () async {
      late http.Request captured;
      final provider = OpenAiCompatibleProvider(
        client: MockClient((req) async {
          captured = req;
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
                'finish_reason': 'length',
              },
            ],
          });
        }),
      );
      final res = await provider.complete(
        request,
        ProviderConfig(baseUrl: 'http://localhost:1234/v1/', model: 'qwen', options: {'jsonMode': 'off'}),
        null,
      );
      expect(res.truncated, isTrue);
      expect(captured.url.toString(), 'http://localhost:1234/v1/chat/completions');
      expect(captured.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['max_tokens'], 1234);
      expect(body.containsKey('response_format'), isFalse);
      expect(body['model'], 'qwen');
    });
  });

  group('Gemini', () {
    test('generateContent request and thought filtering', () async {
      late http.Request captured;
      final provider = GeminiProvider(
        client: MockClient((req) async {
          captured = req;
          return jsonResponse({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'thinking...', 'thought': true},
                    {'text': '{"reels":[]}'},
                  ],
                },
              },
            ],
          });
        }),
      );
      final res = await provider.complete(request, ProviderConfig(model: 'models/gemini-flash-latest'), 'g-key');
      expect(res.text, '{"reels":[]}');
      expect(captured.url.path, '/v1beta/models/gemini-flash-latest:generateContent');
      expect(captured.headers['x-goog-api-key'], 'g-key');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['generationConfig']['responseMimeType'], 'application/json');
      expect(body['generationConfig']['maxOutputTokens'], 1234);
      expect(body['systemInstruction']['parts'][0]['text'], 'sys');
    });

    test('safety stop is an error', () async {
      final provider = GeminiProvider(
        client: MockClient(
          (_) async => jsonResponse({
            'candidates': [
              {
                'finishReason': 'SAFETY',
                'content': {'parts': []},
              },
            ],
          }),
        ),
      );
      await expectLater(provider.complete(request, ProviderConfig(), 'k'), throwsA(isA<AiException>()));
    });
  });
}
