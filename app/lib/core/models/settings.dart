import '../util/json.dart';

/// Non-secret configuration for one AI provider. API keys are kept separately
/// in a `SecretStore` and never serialised with the settings.
class ProviderConfig {
  ProviderConfig({this.model = '', this.baseUrl = '', Map<String, String>? options}) : options = options ?? {};

  String model;
  String baseUrl;

  /// Provider specific options, e.g. `effort` (Anthropic) or `jsonMode` (OpenAI-compatible).
  final Map<String, String> options;

  ProviderConfig copy() => ProviderConfig(model: model, baseUrl: baseUrl, options: Map.of(options));

  Map<String, dynamic> toJson() => {'model': model, 'baseUrl': baseUrl, 'options': options};

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    model: jString(json['model']),
    baseUrl: jString(json['baseUrl']),
    options: jMap(json['options']).map((k, v) => MapEntry(k, jString(v))),
  );
}

class AiSettings {
  AiSettings({this.providerId = 'offline', Map<String, ProviderConfig>? providers, this.maxOutputTokens = 16000})
    : providers = providers ?? {};

  /// Id of the active provider (`offline`, `anthropic`, `openai`, `gemini`, `openai_compatible`).
  String providerId;
  final Map<String, ProviderConfig> providers;
  int maxOutputTokens;

  ProviderConfig configFor(String id) => providers.putIfAbsent(id, ProviderConfig.new);

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'providers': providers.map((k, v) => MapEntry(k, v.toJson())),
    'maxOutputTokens': maxOutputTokens,
  };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
    providerId: jString(json['providerId'], 'offline'),
    providers: jMap(json['providers']).map((k, v) => MapEntry(k, ProviderConfig.fromJson(jMap(v)))),
    maxOutputTokens: jInt(json['maxOutputTokens'], 16000).clamp(1024, 128000),
  );
}

/// How reels are written.
class GenerationSettings {
  GenerationSettings({
    this.difficulty = 'adaptive',
    this.style = 'friendly',
    this.language = 'source',
    this.maxWordsPerReel = 70,
    this.useEmojis = true,
    this.customInstructions = '',
    this.reelsPerRequest = 5,
    this.fallbackToOffline = true,
  });

  /// `adaptive`, `easy`, `medium`, `hard`.
  String difficulty;

  /// `friendly`, `concise`, `academic`, `playful`, `eli5`.
  String style;

  /// `source` = same language as the material, otherwise a language name ("English", "Deutsch", ...).
  String language;
  int maxWordsPerReel;
  bool useEmojis;
  String customInstructions;

  /// How many reels are requested per AI call.
  int reelsPerRequest;

  /// Use the built-in offline generator if the AI call fails.
  bool fallbackToOffline;

  Map<String, dynamic> toJson() => {
    'difficulty': difficulty,
    'style': style,
    'language': language,
    'maxWordsPerReel': maxWordsPerReel,
    'useEmojis': useEmojis,
    'customInstructions': customInstructions,
    'reelsPerRequest': reelsPerRequest,
    'fallbackToOffline': fallbackToOffline,
  };

  factory GenerationSettings.fromJson(Map<String, dynamic> json) => GenerationSettings(
    difficulty: jString(json['difficulty'], 'adaptive'),
    style: jString(json['style'], 'friendly'),
    language: jString(json['language'], 'source'),
    maxWordsPerReel: jInt(json['maxWordsPerReel'], 70).clamp(20, 200),
    useEmojis: jBool(json['useEmojis'], true),
    customInstructions: jString(json['customInstructions']),
    reelsPerRequest: jInt(json['reelsPerRequest'], 5).clamp(1, 12),
    fallbackToOffline: jBool(json['fallbackToOffline'], true),
  );
}

/// How the feed is composed.
class FeedSettings {
  FeedSettings({
    this.prefetchThreshold = 3,
    this.reviewShare = 0.3,
    this.useModeReelMix = true,
    Map<String, double>? reelTypeWeights,
    this.focusSourceId,
  }) : reelTypeWeights = reelTypeWeights ?? {};

  /// Start generating when fewer than this many unseen reels are queued.
  int prefetchThreshold;

  /// Share (0..0.8) of feed slots used for spaced-repetition reviews.
  double reviewShare;

  /// Use each study mode's default reel mix instead of [reelTypeWeights].
  bool useModeReelMix;

  /// Custom reel type mix (type id -> relative weight).
  final Map<String, double> reelTypeWeights;

  /// When set, the feed only shows this source.
  String? focusSourceId;

  Map<String, dynamic> toJson() => {
    'prefetchThreshold': prefetchThreshold,
    'reviewShare': reviewShare,
    'useModeReelMix': useModeReelMix,
    'reelTypeWeights': reelTypeWeights,
    'focusSourceId': focusSourceId,
  };

  factory FeedSettings.fromJson(Map<String, dynamic> json) => FeedSettings(
    prefetchThreshold: jInt(json['prefetchThreshold'], 3).clamp(1, 10),
    reviewShare: jDouble(json['reviewShare'], 0.3).clamp(0.0, 0.8),
    useModeReelMix: jBool(json['useModeReelMix'], true),
    reelTypeWeights: jDoubleMap(json['reelTypeWeights']),
    focusSourceId: jStringOrNull(json['focusSourceId']),
  );
}

/// Pen / stylus behaviour.
class PenSettings {
  PenSettings({
    this.stylusOnly = false,
    this.pressureSensitive = true,
    this.baseWidth = 3.0,
    this.colorValue = 0xFFFFD54F,
    this.stylusDrawsOnReels = true,
  });

  /// Palm rejection: only a stylus draws, fingers keep scrolling.
  bool stylusOnly;
  bool pressureSensitive;
  double baseWidth;
  int colorValue;

  /// A stylus annotates reels directly (fingers still swipe).
  bool stylusDrawsOnReels;

  Map<String, dynamic> toJson() => {
    'stylusOnly': stylusOnly,
    'pressureSensitive': pressureSensitive,
    'baseWidth': baseWidth,
    'colorValue': colorValue,
    'stylusDrawsOnReels': stylusDrawsOnReels,
  };

  factory PenSettings.fromJson(Map<String, dynamic> json) => PenSettings(
    stylusOnly: jBool(json['stylusOnly']),
    pressureSensitive: jBool(json['pressureSensitive'], true),
    baseWidth: jDouble(json['baseWidth'], 3.0).clamp(1.0, 12.0),
    colorValue: jInt(json['colorValue'], 0xFFFFD54F),
    stylusDrawsOnReels: jBool(json['stylusDrawsOnReels'], true),
  );
}

class AppSettings {
  AppSettings({
    AiSettings? ai,
    GenerationSettings? generation,
    FeedSettings? feed,
    PenSettings? pen,
    this.usePdftotext = true,
  }) : ai = ai ?? AiSettings(),
       generation = generation ?? GenerationSettings(),
       feed = feed ?? FeedSettings(),
       pen = pen ?? PenSettings();

  final AiSettings ai;
  final GenerationSettings generation;
  final FeedSettings feed;
  final PenSettings pen;

  /// Desktop: prefer the system `pdftotext` (poppler) for PDF import when installed.
  bool usePdftotext;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'ai': ai.toJson(),
    'generation': generation.toJson(),
    'feed': feed.toJson(),
    'pen': pen.toJson(),
    'usePdftotext': usePdftotext,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    ai: AiSettings.fromJson(jMap(json['ai'])),
    generation: GenerationSettings.fromJson(jMap(json['generation'])),
    feed: FeedSettings.fromJson(jMap(json['feed'])),
    pen: PenSettings.fromJson(jMap(json['pen'])),
    usePdftotext: jBool(json['usePdftotext'], true),
  );
}
