import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../core/models/source.dart';
import '../../core/storage/repositories.dart';
import '../../modules/feed/feed_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/import_flow.dart';
import 'source_detail_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static const formatIcons = {
    'pdf': Icons.picture_as_pdf_outlined,
    'epub': Icons.menu_book_outlined,
    'docx': Icons.description_outlined,
    'markdown': Icons.notes,
    'html': Icons.language,
    'text': Icons.text_snippet_outlined,
    'paste': Icons.content_paste,
  };

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryRepository>();
    context.watch<ProgressRepository>();
    final services = context.read<AppServices>();
    final shares = services.feed.sourceShares();
    final sources = library.sources;
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ImportFlow.showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add material'),
      ),
      body: sources.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_books_outlined, size: 64),
                    const SizedBox(height: 16),
                    const Text('Your library is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Add scripts, books or notes to start learning.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => ImportFlow.showAddSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add material'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: sources.length,
              itemBuilder: (context, i) => _SourceCard(source: sources[i], share: shares[sources[i].id] ?? 0),
            ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, required this.share});
  final StudySource source;
  final double share;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final mode = services.modes.byId(source.study.modeId);
    final completion = mode.completion(services.feed.contextFor(source));
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => SourceDetailScreen(sourceId: source.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: completion,
                      strokeWidth: 5,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                    Icon(LibraryScreen.formatIcons[source.format] ?? Icons.article_outlined),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${source.chunkCount} sections · ${(completion * 100).round()}% done',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(AppTheme.modeIcons[mode.id] ?? Icons.school, size: 16),
                          label: Text(mode.name),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            source.study.includeInFeed ? Icons.dynamic_feed : Icons.visibility_off_outlined,
                            size: 16,
                          ),
                          label: Text(
                            source.study.includeInFeed ? '${(share * 100).round()}% of feed' : 'Hidden from feed',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final feed = context.read<FeedEngine>();
                  switch (v) {
                    case 'focus':
                      services.settings.update((s) => s.feed.focusSourceId = source.id);
                      await feed.refresh();
                    case 'toggle':
                      source.study.includeInFeed = !source.study.includeInFeed;
                      await services.library.updateSource(source);
                      await feed.refresh();
                    case 'delete':
                      if (context.mounted && await confirmDelete(context, source)) {
                        await services.deleteSource(source.id);
                      }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'focus', child: Text('Study only this')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(source.study.includeInFeed ? 'Hide from feed' : 'Show in feed'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, StudySource source) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete source?'),
        content: Text('"${source.title}" and all its reels, progress and annotations will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;
