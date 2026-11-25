import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/models/settings.dart';

/// A provider-neutral text generation request.
class AiRequest {
  const AiRequest({required this.system, required this.prompt, this.jsonSchema, this.maxOutputTokens = 16000});

  final String system;
  final String prompt;

  /// When set, providers that support it constrain the output to this schema.
  final Map<String, Object?>? jsonSchema;
  final int maxOutputTokens;
}

class AiResponse {
  const AiResponse({
    required this.text,
    required this.model,
    this.inputTokens,
    this.outputTokens,
    this.truncated = false,
  });
  final String text;
  final String model;
  final int? inputTokens;
  final int? outputTokens;

  /// The model hit the output token limit.
  final bool truncated;
}

class AiException implements Exception {
  AiException(this.message, {this.statusCode, this.retryable = false});
  final String message;
  final int? statusCode;
  final bool retryable;
  @override
  String toString() => message;
}

/// Describes a configurable field shown in Settings for a provider.
class ProviderOption {
  const ProviderOption({
    required this.key,
    required this.label,
    this.help = '',
    this.choices = const {},
    this.defaultValue = '',
  });
  final String key;
  final String label;
  final String help;

  /// Value -> label; empty = free text.
  final Map<String, String> choices;
  final String defaultValue;
}

/// Interface every AI backend implements. Add new backends in
/// `modules/ai/providers/` and register them in `ProviderRegistry`.
abstract class AiProvider {
  String get id;
  String get displayName;
  String get description;
  bool get requiresApiKey;
  bool get supportsBaseUrl;
  String get defaultModel;
  String get defaultBaseUrl;
  List<String> get suggestedModels;

  /// Where users get an API key.
  String get apiKeyHelp;
  List<ProviderOption> get options => const [];

  Future<AiResponse> complete(AiRequest request, ProviderConfig config, String? apiKey);

  Future<List<String>> listModels(ProviderConfig config, String? apiKey);
}

/// Shared HTTP plumbing for HTTP/JSON based providers.
abstract class HttpAiProvider extends AiProvider {
  HttpAiProvider({http.Client? client}) : _client = client; // ignore: prefer_initializing_formals

  http.Client? _client;

  http.Client get client => _client ??= IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      // Respect HTTPS_PROXY/NO_PROXY like other desktop tools.
      ..findProxy = HttpClient.findProxyFromEnvironment,
  );

  Duration get timeout => const Duration(minutes: 4);

  String baseUrl(ProviderConfig config) {
    final url = config.baseUrl.trim().isEmpty ? defaultBaseUrl : config.baseUrl.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String model(ProviderConfig config) => config.model.trim().isEmpty ? defaultModel : config.model.trim();

  Future<Map<String, dynamic>> postJson(Uri uri, Map<String, String> headers, Map<String, Object?> body) async {
    final http.Response response;
    try {
      response = await client
          .post(uri, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw AiException('The AI request timed out.', retryable: true);
    } on SocketException catch (e) {
      throw AiException('Network error: ${e.message}', retryable: true);
    } on http.ClientException catch (e) {
      throw AiException('Network error: ${e.message}', retryable: true);
    }
    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> getJson(Uri uri, Map<String, String> headers) async {
    final http.Response response;
    try {
      response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw AiException('The request timed out.', retryable: true);
    } on SocketException catch (e) {
      throw AiException('Network error: ${e.message}', retryable: true);
    } on http.ClientException catch (e) {
      throw AiException('Network error: ${e.message}', retryable: true);
    }
    return decodeResponse(response);
  }

  Map<String, dynamic> decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map<String, dynamic>) return decoded;
    final message = _errorMessage(decoded) ?? 'HTTP ${response.statusCode}';
    final code = response.statusCode;
    final friendly = switch (code) {
      401 || 403 => 'Authentication failed — check your API key. ($message)',
      404 => 'Not found — check the model name and base URL. ($message)',
      429 => 'Rate limit or quota reached. ($message)',
      >= 500 => 'The AI service is having problems. ($message)',
      _ => message,
    };
    throw AiException(friendly, statusCode: code, retryable: code == 429 || code >= 500);
  }

  static String? _errorMessage(Object? decoded) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) return error['message'] as String;
      if (error is String) return error;
      if (decoded['message'] is String) return decoded['message'] as String;
    }
    if (decoded is List && decoded.isNotEmpty) return _errorMessage(decoded.first);
    return null;
  }
}
