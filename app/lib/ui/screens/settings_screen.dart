import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../core/models/languages.dart';
import '../../core/models/settings.dart';
import '../../core/storage/repositories.dart';
import '../../core/storage/settings_repository.dart';
import '../../modules/ai/ai_provider.dart';
import '../../modules/ai/provider_registry.dart';
import '../../modules/ai/providers/openai_provider.dart';
import '../../modules/reels/reel_types.dart';
import '../../modules/speech/speech_controller.dart';
import '../../modules/speech/speech_engine.dart';
import '../pen/pen_canvas.dart';
import '../widgets/readable_width.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: const [
            _Section(title: 'AI provider', icon: Icons.smart_toy_outlined, child: _AiSettings()),
            _Section(title: 'Reel generation', icon: Icons.auto_awesome_outlined, child: _GenerationSettings()),
            _Section(title: 'Feed', icon: Icons.dynamic_feed_outlined, child: _FeedSettings()),
            _Section(title: 'Audio', icon: Icons.headphones_outlined, child: _AudioSettings()),
            _Section(title: 'Pen & stylus', icon: Icons.draw_outlined, child: _PenSettings()),
            _Section(title: 'Data', icon: Icons.storage_outlined, child: _DataSettings()),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------

class _AiSettings extends StatefulWidget {
  const _AiSettings();

  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  bool _showKey = false;
  bool _testing = false;
  String? _testResult;
  String? _loadedFor;
  Timer? _keyDebounce;

  @override
  void dispose() {
    _keyDebounce?.cancel();
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _ensureLoaded(AiProvider? provider, SettingsRepository repo) {
    if (provider == null || _loadedFor == provider.id) return;
    _loadedFor = provider.id;
    // Fill the text fields after this frame (controllers must not change during build).
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(provider, repo));
  }

  Future<void> _load(AiProvider provider, SettingsRepository repo) async {
    final config = repo.settings.ai.configFor(provider.id);
    _model.text = config.model;
    _baseUrl.text = config.baseUrl;
    _key.text = await repo.readSecret(ProviderRegistry.secretKey(provider.id)) ?? '';
    _testResult = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SettingsRepository>();
    final services = context.read<AppServices>();
    final ai = repo.settings.ai;
    final provider = services.providers.byId(ai.providerId);
    _ensureLoaded(provider, repo);
    final config = provider == null ? null : ai.configFor(provider.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: ai.providerId,
          decoration: const InputDecoration(labelText: 'Provider', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: offlineProviderId, child: Text('Offline (built-in, no AI key)')),
            for (final p in services.providers.providers) DropdownMenuItem(value: p.id, child: Text(p.displayName)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _loadedFor = null;
            repo.update((s) => s.ai.providerId = v);
            services.feed.refresh();
          },
        ),
        const SizedBox(height: 8),
        if (provider == null)
          const Text(
            'The offline generator builds simple reels (gap texts, quizzes, key points) directly from your material — '
            'no internet or subscription needed. Choose an AI provider and enter your own API key for much better, '
            'more varied reels.',
          )
        else ...[
          Text(provider.description),
          const SizedBox(height: 4),
          Text(provider.apiKeyHelp, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: provider.requiresApiKey ? 'API key' : 'API key (optional)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (v) {
              _keyDebounce?.cancel();
              _keyDebounce = Timer(const Duration(milliseconds: 500), () {
                repo.writeSecret(ProviderRegistry.secretKey(provider.id), v.trim());
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _model,
                  decoration: InputDecoration(
                    labelText: 'Model',
                    hintText: provider.defaultModel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => repo.update((s) => s.ai.configFor(provider.id).model = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickModel(provider, config!),
                icon: const Icon(Icons.list),
                label: const Text('Browse'),
              ),
            ],
          ),
          if (provider.suggestedModels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final m in provider.suggestedModels)
                  ActionChip(
                    label: Text(m),
                    onPressed: () {
                      _model.text = m;
                      repo.update((s) => s.ai.configFor(provider.id).model = m);
                    },
                  ),
              ],
            ),
          ],
          if (provider.supportsBaseUrl) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _baseUrl,
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      hintText: provider.defaultBaseUrl,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => repo.update((s) => s.ai.configFor(provider.id).baseUrl = v.trim()),
                  ),
                ),
                if (provider is OpenAiCompatibleProvider)
                  PopupMenuButton<String>(
                    tooltip: 'Presets',
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    onSelected: (url) {
                      _baseUrl.text = url;
                      repo.update((s) => s.ai.configFor(provider.id).baseUrl = url);
                    },
                    itemBuilder: (_) => [
                      for (final e in OpenAiCompatibleProvider.presets.entries)
                        PopupMenuItem(value: e.value, child: Text('${e.key} — ${e.value}')),
                    ],
                  ),
              ],
            ),
          ],
          for (final option in provider.options) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${provider.id}.${option.key}'),
              initialValue: config!.options[option.key] ?? option.defaultValue,
              decoration: InputDecoration(
                labelText: option.label,
                helperText: option.help,
                border: const OutlineInputBorder(),
              ),
              items: [for (final c in option.choices.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
              onChanged: (v) => repo.update((s) => s.ai.configFor(provider.id).options[option.key] = v ?? ''),
            ),
          ],
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final limit = repo.settings.generation.maxAiRequestsPerDay;
              final used = services.progress.stats.aiRequestsOn(DateTime.now());
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    limit == 0
                        ? 'Daily AI request limit: unlimited (today: $used)'
                        : 'Daily AI request limit: $limit (today: $used of $limit)',
                  ),
                  Slider(
                    value: limit.toDouble().clamp(0, 200),
                    min: 0,
                    max: 200,
                    divisions: 40,
                    label: limit == 0 ? 'unlimited' : '$limit',
                    onChanged: (v) => repo.update((s) => s.generation.maxAiRequestsPerDay = v.round()),
                  ),
                  Text(
                    'When the limit is reached the feed shows saved reels (and offline reels if enabled). '
                    '0 = unlimited.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
          Text('Max output tokens per request: ${ai.maxOutputTokens}'),
          Slider(
            value: ai.maxOutputTokens.toDouble().clamp(2000, 64000),
            min: 2000,
            max: 64000,
            divisions: 31,
            onChanged: (v) => repo.update((s) => s.ai.maxOutputTokens = v.round()),
          ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _testing
                    ? null
                    : () async {
                        _keyDebounce?.cancel();
                        await repo.writeSecret(ProviderRegistry.secretKey(provider.id), _key.text.trim());
                        setState(() {
                          _testing = true;
                          _testResult = null;
                        });
                        String result;
                        try {
                          result = await services.generation.testConnection();
                        } catch (e) {
                          result = 'Failed: $e';
                        }
                        if (mounted) {
                          setState(() {
                            _testing = false;
                            _testResult = result;
                          });
                        }
                      },
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Test connection'),
              ),
            ],
          ),
          if (_testResult != null) ...[const SizedBox(height: 8), SelectableText(_testResult!)],
        ],
      ],
    );
  }

  Future<void> _pickModel(AiProvider provider, ProviderConfig config) async {
    final repo = context.read<SettingsRepository>();
    final messenger = ScaffoldMessenger.of(context);
    _keyDebounce?.cancel();
    await repo.writeSecret(ProviderRegistry.secretKey(provider.id), _key.text.trim());
    List<String> models;
    try {
      models = await provider.listModels(config, _key.text.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not load models: $e')));
      return;
    }
    if (!mounted) return;
    if (models.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('The provider returned no models.')));
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a model'),
        children: [
          SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [for (final m in models) ListTile(title: Text(m), onTap: () => Navigator.pop(context, m))],
            ),
          ),
        ],
      ),
    );
    if (chosen != null) {
      _model.text = chosen;
      repo.update((s) => s.ai.configFor(provider.id).model = chosen);
    }
  }
}

// ---------------------------------------------------------------------------

class _GenerationSettings extends StatefulWidget {
  const _GenerationSettings();

  @override
  State<_GenerationSettings> createState() => _GenerationSettingsState();
}

class _GenerationSettingsState extends State<_GenerationSettings> {
  late final TextEditingController _instructions = TextEditingController(
    text: context.read<SettingsRepository>().settings.generation.customInstructions,
  );

  static const languages = ['source', ...reelLanguages];
  static const styles = {
    'friendly': 'Friendly tutor',
    'concise': 'Concise',
    'academic': 'Academic',
    'playful': 'Playful',
    'eli5': 'Explain like I\'m 12',
  };

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SettingsRepository>();
    final g = repo.settings.generation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Difficulty'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'adaptive', label: Text('Adaptive')),
            ButtonSegment(value: 'easy', label: Text('Easy')),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'hard', label: Text('Hard')),
          ],
          selected: {g.difficulty},
          onSelectionChanged: (v) => repo.update((s) => s.generation.difficulty = v.first),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: styles.containsKey(g.style) ? g.style : 'friendly',
                decoration: const InputDecoration(labelText: 'Style', border: OutlineInputBorder()),
                items: [for (final e in styles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => repo.update((s) => s.generation.style = v ?? 'friendly'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: languages.contains(g.language) ? g.language : 'source',
                decoration: const InputDecoration(labelText: 'Default reel language', border: OutlineInputBorder()),
                items: [
                  for (final l in languages)
                    DropdownMenuItem(value: l, child: Text(l == 'source' ? 'Same as material' : l)),
                ],
                onChanged: (v) => repo.update((s) => s.generation.language = v ?? 'source'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Max words per reel: ${g.maxWordsPerReel}'),
        Slider(
          value: g.maxWordsPerReel.toDouble(),
          min: 20,
          max: 150,
          divisions: 26,
          onChanged: (v) => repo.update((s) => s.generation.maxWordsPerReel = v.round()),
        ),
        Text('Reels per generation request: ${g.reelsPerRequest}'),
        Slider(
          value: g.reelsPerRequest.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          onChanged: (v) => repo.update((s) => s.generation.reelsPerRequest = v.round()),
        ),
        const SizedBox(height: 6),
        const Text('Visuals: graphs, charts, sketches, equations, figures'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'off', label: Text('Off')),
            ButtonSegment(value: 'some', label: Text('Some')),
            ButtonSegment(value: 'lots', label: Text('Lots')),
          ],
          selected: {g.visualLevel},
          onSelectionChanged: (v) => repo.update((s) => s.generation.visualLevel = v.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow images from the internet in visuals'),
          subtitle: const Text('Off: only figures from your own material are shown (no requests to image hosts).'),
          value: g.allowWebImages,
          onChanged: (v) => repo.update((s) => s.generation.allowWebImages = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use emojis'),
          value: g.useEmojis,
          onChanged: (v) => repo.update((s) => s.generation.useEmojis = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fall back to offline generator on AI errors'),
          subtitle: const Text('Keeps the feed going when the AI is unreachable.'),
          value: g.fallbackToOffline,
          onChanged: (v) => repo.update((s) => s.generation.fallbackToOffline = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _instructions,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Custom instructions for the AI',
            hintText: 'e.g. "Use examples from medicine", "Always give the English term in brackets"',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => repo.update((s) => s.generation.customInstructions = v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _FeedSettings extends StatelessWidget {
  const _FeedSettings();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SettingsRepository>();
    final library = context.watch<LibraryRepository>();
    final services = context.read<AppServices>();
    final f = repo.settings.feed;
    final shares = services.feed.sourceShares();
    final included = library.sources.where((s) => s.study.includeInFeed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Generate new reels when fewer than ${f.prefetchThreshold} are queued'),
        Slider(
          value: f.prefetchThreshold.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (v) => repo.update((s) => s.feed.prefetchThreshold = v.round()),
        ),
        Text('Share of reviews (spaced repetition): ${(f.reviewShare * 100).round()}%'),
        Slider(
          value: f.reviewShare,
          min: 0,
          max: 0.8,
          divisions: 16,
          onChanged: (v) => repo.update((s) => s.feed.reviewShare = v),
        ),
        const Divider(),
        const Text('Sources in the feed', style: TextStyle(fontWeight: FontWeight.w700)),
        if (included.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No sources in the feed yet.')),
        for (final s in included)
          Row(
            children: [
              Expanded(flex: 3, child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 4,
                child: Slider(
                  value: s.study.feedWeight.clamp(0.1, 10),
                  min: 0.1,
                  max: 10,
                  onChanged: (v) {
                    s.study.feedWeight = v;
                    library.updateSource(s);
                  },
                ),
              ),
              SizedBox(width: 44, child: Text('${((shares[s.id] ?? 0) * 100).round()}%', textAlign: TextAlign.end)),
            ],
          ),
        const Divider(),
        const Text('Saving AI costs', style: TextStyle(fontWeight: FontWeight.w700)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show seen reels again'),
          subtitle: const Text('Re-uses saved reels after a while instead of generating new ones.'),
          value: f.reuseReels,
          onChanged: (v) => repo.update((s) => s.feed.reuseReels = v),
        ),
        if (f.reuseReels)
          DropdownButtonFormField<int>(
            initialValue: const [6, 12, 24, 72, 168].contains(f.reuseAfterHours) ? f.reuseAfterHours : 24,
            decoration: const InputDecoration(labelText: 'Show a reel again after', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 6, child: Text('6 hours')),
              DropdownMenuItem(value: 12, child: Text('12 hours')),
              DropdownMenuItem(value: 24, child: Text('1 day')),
              DropdownMenuItem(value: 72, child: Text('3 days')),
              DropdownMenuItem(value: 168, child: Text('1 week')),
            ],
            onChanged: (v) => repo.update((s) => s.feed.reuseAfterHours = v ?? 24),
          ),
        const SizedBox(height: 8),
        Text(
          f.retireAfterViews == 0
              ? 'Keep reels forever'
              : 'Delete a reel after you have seen it ${f.retireAfterViews} times',
        ),
        Slider(
          value: f.retireAfterViews.toDouble().clamp(0, 15),
          min: 0,
          max: 15,
          divisions: 15,
          label: f.retireAfterViews == 0 ? 'never' : '${f.retireAfterViews}',
          onChanged: (v) => repo.update((s) => s.feed.retireAfterViews = v.round()),
        ),
        Text(
          'Saved (bookmarked) reels and reels you got wrong last time are kept. '
          '${services.progress.stats.reelsRetired} reels deleted so far.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Neutral background for math reels'),
          subtitle: const Text('Calm graph-paper look for formulas, theorems, recipes and plots.'),
          value: f.neutralMathBackground,
          onChanged: (v) => repo.update((s) => s.feed.neutralMathBackground = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use the study mode\'s reel mix'),
          subtitle: const Text('Turn off to set your own mix of reel types.'),
          value: f.useModeReelMix,
          onChanged: (v) => repo.update((s) {
            s.feed.useModeReelMix = v;
            if (!v && s.feed.reelTypeWeights.isEmpty) {
              for (final t in ReelTypes.all) {
                s.feed.reelTypeWeights[t.id] = 1;
              }
            }
          }),
        ),
        if (!f.useModeReelMix)
          for (final t in ReelTypes.all)
            Row(
              children: [
                Expanded(flex: 3, child: Text(t.label)),
                Expanded(
                  flex: 4,
                  child: Slider(
                    value: (f.reelTypeWeights[t.id] ?? 0).clamp(0, 5),
                    min: 0,
                    max: 5,
                    divisions: 10,
                    onChanged: (v) => repo.update((s) => s.feed.reelTypeWeights[t.id] = v),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text((f.reelTypeWeights[t.id] ?? 0).toStringAsFixed(1), textAlign: TextAlign.end),
                ),
              ],
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            services.feed.refresh();
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Upcoming reels will use the new settings.')));
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Apply to upcoming reels now'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AudioSettings extends StatefulWidget {
  const _AudioSettings();

  @override
  State<_AudioSettings> createState() => _AudioSettingsState();
}

class _AudioSettingsState extends State<_AudioSettings> {
  @override
  void initState() {
    super.initState();
    context.read<SpeechController>().checkAvailable();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SettingsRepository>();
    final speech = context.watch<SpeechController>();
    final a = repo.settings.audio;
    final theme = Theme.of(context);
    final available = speech.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              available == false ? Icons.volume_off_outlined : Icons.record_voice_over_outlined,
              size: 18,
              color: available == false ? theme.colorScheme.error : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                available == null
                    ? 'Checking the voice…'
                    : available
                    ? 'Voice: ${speech.engine.name}'
                    : 'No voice found.',
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Test'),
              onPressed: available == true
                  ? () => speech.engine.speak(
                      'Hello! This is how UnRot reads your reels.',
                      languageCode: 'en-US',
                      rate: a.rate,
                    )
                  : null,
            ),
          ],
        ),
        if (available == false && speech.engine is CommandSpeechEngine)
          Text(
            'Install a speech engine, e.g. "sudo apt install espeak-ng" (Debian/Ubuntu), '
            '"sudo dnf install espeak-ng" (Fedora) or "sudo pacman -S espeak-ng" (Arch), then restart UnRot.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hands-free: read every reel aloud'),
          subtitle: const Text('Same as the headphones button in the feed.'),
          value: a.autoRead,
          onChanged: (v) => repo.update((s) => s.audio.autoRead = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Continue to the next reel automatically'),
          subtitle: const Text(
            'In hands-free mode: questions wait a few seconds for your answer, then the solution is read.',
          ),
          value: a.autoAdvance,
          onChanged: (v) => repo.update((s) => s.audio.autoAdvance = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Read the solution after answering'),
          value: a.readAnswers,
          onChanged: (v) => repo.update((s) => s.audio.readAnswers = v),
        ),
        Text('Speaking speed: ${a.rate.toStringAsFixed(2)}×'),
        Slider(
          value: a.rate,
          min: 0.5,
          max: 2.0,
          divisions: 12,
          label: '${a.rate.toStringAsFixed(2)}×',
          onChanged: (v) => repo.update((s) => s.audio.rate = v),
        ),
        Text(
          'Formulas are read in words ("x squared", "integral from 0 to 1"). Reels use the voice of their language.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PenSettings extends StatelessWidget {
  const _PenSettings();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SettingsRepository>();
    final p = repo.settings.pen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stylus draws directly on reels'),
          subtitle: const Text('Annotate any reel with your pen; fingers keep swiping.'),
          value: p.stylusDrawsOnReels,
          onChanged: (v) => repo.update((s) => s.pen.stylusDrawsOnReels = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stylus only (palm rejection)'),
          subtitle: const Text('Ignore finger and mouse input on drawing surfaces.'),
          value: p.stylusOnly,
          onChanged: (v) => repo.update((s) => s.pen.stylusOnly = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pressure sensitivity'),
          value: p.pressureSensitive,
          onChanged: (v) => repo.update((s) => s.pen.pressureSensitive = v),
        ),
        Text('Pen width: ${p.baseWidth.toStringAsFixed(1)}'),
        Slider(value: p.baseWidth, min: 1, max: 12, onChanged: (v) => repo.update((s) => s.pen.baseWidth = v)),
        const Text('Default ink'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          children: [
            for (final c in PenToolbar.colors)
              GestureDetector(
                onTap: () => repo.update((s) => s.pen.colorValue = c.toARGB32()),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: p.colorValue == c.toARGB32() ? Colors.white : Colors.transparent,
                  child: CircleAvatar(radius: 13, backgroundColor: c),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Test area', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const _PenTestPad(),
      ],
    );
  }
}

class _PenTestPad extends StatefulWidget {
  const _PenTestPad();

  @override
  State<_PenTestPad> createState() => _PenTestPadState();
}

class _PenTestPadState extends State<_PenTestPad> {
  PenController? _pen;

  @override
  void dispose() {
    _pen?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsRepository>().settings.pen;
    _pen ??= PenController(color: Color(p.colorValue), width: p.baseWidth);
    _pen!.width = p.baseWidth;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 160,
        color: Colors.black26,
        child: Stack(
          children: [
            Positioned.fill(
              child: PenCanvas(controller: _pen!, settings: p),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _pen!.clear),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DataSettings extends StatelessWidget {
  const _DataSettings();

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final repo = context.watch<SettingsRepository>();
    final reels = context.watch<ReelRepository>();
    final desktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (desktop)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use system pdftotext as PDF fallback'),
            subtitle: const Text(
              'If poppler-utils is installed, it is used when the built-in PDF reader finds little text.',
            ),
            value: repo.settings.usePdftotext,
            onChanged: (v) {
              repo.update((s) => s.usePdftotext = v);
              services.ingestion.allowPdfSystemFallback = v;
            },
          ),
        const Text('Data folder'),
        SelectableText(services.dataDirectory.path, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '${services.library.sources.length} sources · ${reels.count} generated reels',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.layers_clear_outlined),
              label: const Text('Delete generated reels'),
              onPressed: () async {
                if (await _confirm(
                  context,
                  'Delete all generated reels?',
                  'Your sources stay. New reels will be generated with your current settings.',
                )) {
                  await services.reels.clear(services.library.sources.map((s) => s.id));
                  await services.feed.refresh();
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset progress'),
              onPressed: () async {
                if (await _confirm(
                  context,
                  'Reset all progress?',
                  'Mastery, statistics and review schedules will be cleared.',
                )) {
                  services.progress.resetAll();
                  await services.feed.refresh();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('UnRot · open source under GPL-3.0', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static Future<bool> _confirm(BuildContext context, String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
          ],
        ),
      ) ??
      false;
}
