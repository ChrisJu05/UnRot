import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../core/models/progress.dart';
import '../../core/storage/repositories.dart';
import '../../modules/study/modes/builtin_modes.dart';
import '../theme/app_theme.dart';
import 'source_detail_screen.dart';
import '../widgets/readable_width.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();
    final library = context.watch<LibraryRepository>();
    final services = context.read<AppServices>();
    final now = DateTime.now();
    final stats = progress.stats;
    final accuracy = stats.totalAnswered == 0 ? null : stats.totalCorrect / stats.totalAnswered;
    final due = progress.reelStates.where((r) => r.isDue(now) && services.reels.reel(r.reelId) != null).length;
    final saved = progress.reelStates.where((r) => r.bookmarked).length;
    final theme = Theme.of(context);

    final weak = progress.chunkProgress.where((c) => c.answered >= 2 && c.mastery < 0.55).toList()
      ..sort((a, b) => a.mastery.compareTo(b.mastery));

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatTile(icon: '🔥', value: '${stats.streak(now)}', label: 'day streak'),
                _StatTile(icon: '🎬', value: '${stats.reelsOn(now)}', label: 'reels today'),
                _StatTile(icon: '📈', value: '${stats.totalReels}', label: 'reels total'),
                _StatTile(icon: '🎯', value: accuracy == null ? '–' : '${(accuracy * 100).round()}%', label: 'correct'),
                _StatTile(icon: '🔁', value: '$due', label: 'reviews due'),
                _StatTile(icon: '🔖', value: '$saved', label: 'saved'),
              ],
            ),
            const SizedBox(height: 20),
            Text('Last 14 days', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _ActivityChart(stats: stats, now: now),
            const SizedBox(height: 24),
            Text('Sources', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (library.sources.isEmpty) const Text('No sources yet.'),
            for (final s in library.sources)
              Builder(
                builder: (context) {
                  final mode = services.modes.byId(s.study.modeId);
                  final ctx = services.feed.contextFor(s);
                  final completion = mode.completion(ctx);
                  final chunks = library.chunks(s.id);
                  final mastery = chunks.isEmpty
                      ? 0.0
                      : chunks.map((c) => progress.peekChunk(c.id)?.mastery ?? 0).reduce((a, b) => a + b) /
                            chunks.length;
                  final days = mode.id == 'exam' ? ExamPrepMode.daysLeft(ctx) : null;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      onTap: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => SourceDetailScreen(sourceId: s.id))),
                      leading: Icon(AppTheme.modeIcons[mode.id] ?? Icons.school),
                      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: completion,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${mode.name} · ${(completion * 100).round()}% done · mastery ${(mastery * 100).round()}%'
                            '${days != null ? ' · exam in $days days' : ''}',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Weak spots', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final c in weak.take(8))
                Builder(
                  builder: (context) {
                    final chunk = library.chunk(c.chunkId);
                    final source = library.source(c.sourceId);
                    if (chunk == null || source == null) return const SizedBox.shrink();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        leading: CircularProgressIndicator(
                          value: c.mastery,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                        title: Text(chunk.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${source.title} · ${_statusText(c)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => services.feed.setFocusChunk(chunk.id),
                          child: const Text('Practice'),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusText(ChunkProgress c) =>
      '${(c.mastery * 100).round()}% mastery${c.accuracy != null ? ', ${(c.accuracy! * 100).round()}% correct' : ''}';
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});
  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.stats, required this.now});
  final StudyStats stats;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(14, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 13 - i)));
    final counts = days.map(stats.reelsOn).toList();
    final maxCount = max(1, counts.reduce(max));
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
        child: SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${MaterialLocalizations.of(context).formatShortMonthDay(days[i])}: ${counts[i]} reels',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: 90 * counts[i] / maxCount + 2,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: counts[i] == 0 ? color.withValues(alpha: 0.15) : color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${days[i].day}', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
