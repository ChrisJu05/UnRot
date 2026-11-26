import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../core/models/languages.dart';
import '../../core/models/progress.dart';
import '../../core/storage/repositories.dart';
import '../../modules/feed/feed_engine.dart';
import '../../modules/generation/generation_job.dart';
import '../../modules/study/modes/builtin_modes.dart';
import '../theme/app_theme.dart';
import 'library_screen.dart';
import '../widgets/readable_width.dart';

/// Study settings and section progress for one source.
class SourceDetailScreen extends StatefulWidget {
  const SourceDetailScreen({super.key, required this.sourceId});
  final String sourceId;

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> {
  late final TextEditingController _focusNote;
  late final FeedEngine _feed;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _feed = context.read<FeedEngine>();
    final source = context.read<LibraryRepository>().source(widget.sourceId);
    _focusNote = TextEditingController(text: source?.study.focusNote ?? '');
  }

  @override
  void dispose() {
    _focusNote.dispose();
    if (_dirty) {
      // Apply changed study settings to upcoming reels.
      _feed.refresh();
    }
    super.dispose();
  }

  Future<void> _save(void Function() change) async {
    final library = context.read<LibraryRepository>();
    final source = library.source(widget.sourceId);
    if (source == null) return;
    change();
    _dirty = true;
    await library.updateSource(source);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryRepository>();
    final progress = context.watch<ProgressRepository>();
    final services = context.read<AppServices>();
    final source = library.source(widget.sourceId);
    if (source == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This source no longer exists.')),
      );
    }
    final chunks = library.chunks(source.id);
    final mode = services.modes.byId(source.study.modeId);
    final ctx = services.feed.contextFor(source);
    final theme = Theme.of(context);
    final shares = services.feed.sourceShares();
    final days = source.study.examDate == null ? null : ExamPrepMode.daysLeft(ctx);
    final pace = mode.id == 'exam' ? ExamPrepMode.requiredPace(ctx, mode) : null;

    return CallbackShortcuts(
      // Desktop: Escape goes back.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(source.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final controller = TextEditingController(text: source.title);
                  final name = await showDialog<String>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Rename source'),
                      content: TextField(controller: controller, autofocus: true),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Save')),
                      ],
                    ),
                  );
                  if (name != null && name.trim().isNotEmpty) await _save(() => source.title = name.trim());
                },
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirmDelete(context, source)) {
                    await services.deleteSource(source.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ReadableWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('Study mode', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final m in services.modes.all)
                  Card(
                    color: m.id == mode.id ? theme.colorScheme.primaryContainer : null,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(AppTheme.modeIcons[m.id] ?? Icons.school),
                      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(m.id == mode.id ? m.description : m.tagline),
                      trailing: m.id == mode.id ? const Icon(Icons.check_circle) : null,
                      onTap: () => _save(() => source.study.modeId = m.id),
                    ),
                  ),
                if (mode.id == 'exam') ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(
                        source.study.examDate == null
                            ? 'Set exam date'
                            : 'Exam: ${MaterialLocalizations.of(context).formatMediumDate(source.study.examDate!)}',
                      ),
                      subtitle: Text(
                        days == null
                            ? 'Used to pace the material and increase reviews before the exam.'
                            : '$days days left · ${pace?.toStringAsFixed(1) ?? '-'} sections per day needed',
                      ),
                      trailing: source.study.examDate == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _save(() => source.study.examDate = null),
                            ),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: source.study.examDate ?? now.add(const Duration(days: 14)),
                          firstDate: now.subtract(const Duration(days: 1)),
                          lastDate: now.add(const Duration(days: 730)),
                        );
                        if (picked != null) await _save(() => source.study.examDate = picked);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Reel language', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('lang-${source.id}'),
                  initialValue: source.study.reelLanguage,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    helperText:
                        services.generation.usesOffline &&
                            GenerationJob.effectiveLanguage(source, services.settings.settings.generation) != 'source'
                        ? 'Translation needs an AI provider. The offline generator keeps the source language.'
                        : 'Reels can be in the material\'s own language or translated, e.g. into English.',
                    helperMaxLines: 2,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('App default (${languageLabel(services.settings.settings.generation.language)})'),
                    ),
                    const DropdownMenuItem(value: 'source', child: Text('Same as the source')),
                    for (final l in reelLanguages) DropdownMenuItem(value: l, child: Text(l)),
                  ],
                  onChanged: (v) => _save(() => source.study.reelLanguage = v ?? 'default'),
                ),
                const SizedBox(height: 20),
                Text('Feed', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show in feed'),
                  value: source.study.includeInFeed,
                  onChanged: (v) => _save(() => source.study.includeInFeed = v),
                ),
                if (source.study.includeInFeed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Feed share: ${((shares[source.id] ?? 0) * 100).round()}%'),
                    subtitle: Slider(
                      value: source.study.feedWeight.clamp(0.1, 10),
                      min: 0.1,
                      max: 10,
                      divisions: 99,
                      label: source.study.feedWeight.toStringAsFixed(1),
                      onChanged: (v) => _save(() => source.study.feedWeight = v),
                    ),
                  ),
                TextField(
                  controller: _focusNote,
                  decoration: const InputDecoration(
                    labelText: 'Focus / notes for the AI (optional)',
                    hintText: 'e.g. "Focus on formulas", "Skip the history parts", "Exam is multiple choice"',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (v) => _save(() => source.study.focusNote = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    services.settings.update((s) => s.feed.focusSourceId = source.id);
                    await services.feed.setFocusChunk(null);
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('Study only this source now'),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sections (${chunks.length})',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('${(mode.completion(ctx) * 100).round()}% complete'),
                  ],
                ),
                const SizedBox(height: 8),
                for (final c in chunks)
                  Builder(
                    builder: (context) {
                      final p = progress.peekChunk(c.id);
                      final status = p?.status ?? ChunkStatus.unseen;
                      final done = mode.isComplete(p);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status).withValues(alpha: 0.25),
                            child: done
                                ? Icon(Icons.check, color: _statusColor(status))
                                : Text(
                                    '${c.index + 1}',
                                    style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700),
                                  ),
                          ),
                          title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: p?.mastery ?? 0,
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p == null
                                    ? '${c.wordCount} words · not started'
                                    : '${_statusLabel(status)} · ${p.reelsSeen} reels${p.accuracy != null ? ' · ${(p.accuracy! * 100).round()}% correct' : ''}',
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Study this section',
                            icon: const Icon(Icons.play_circle_outline),
                            onPressed: () async {
                              _dirty = false;
                              await services.feed.setFocusChunk(c.id);
                              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                            },
                          ),
                          onTap: () => _showChunk(context, c.title, c.plainText),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(ChunkStatus s) => switch (s) {
    ChunkStatus.unseen => Colors.grey,
    ChunkStatus.learning => const Color(0xFFFFB74D),
    ChunkStatus.reviewing => const Color(0xFF4FC3F7),
    ChunkStatus.mastered => const Color(0xFF81C784),
  };

  static String _statusLabel(ChunkStatus s) => switch (s) {
    ChunkStatus.unseen => 'Not started',
    ChunkStatus.learning => 'Learning',
    ChunkStatus.reviewing => 'Reviewing',
    ChunkStatus.mastered => 'Mastered',
  };

  void _showChunk(BuildContext context, String title, String text) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SelectableText(text, style: const TextStyle(height: 1.5)),
        ],
      ),
    ),
  );
}
