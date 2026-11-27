import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/util/text.dart';
import '../../app/app_services.dart';
import '../../core/storage/repositories.dart';
import '../../modules/exchange/reel_exchange.dart';
import '../../modules/study/subjects.dart';
import '../theme/app_theme.dart';

/// Generate reels with a chat subscription (Claude Pro, ChatGPT Plus, Gemini…)
/// instead of an API key: copy a prompt, paste the answer back.
class ChatExchangePanel extends StatefulWidget {
  const ChatExchangePanel({super.key, required this.sourceId});
  final String sourceId;

  @override
  State<ChatExchangePanel> createState() => _ChatExchangePanelState();
}

class _ChatExchangePanelState extends State<ChatExchangePanel> {
  int? _from;
  int? _to;
  int _perSection = 6;
  static const _exchange = ReelExchange();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryRepository>();
    final services = context.read<AppServices>();
    final source = library.source(widget.sourceId);
    if (source == null) return const SizedBox.shrink();
    final chunks = library.chunks(source.id);
    if (chunks.isEmpty) return const SizedBox.shrink();
    // Default range: the first sections that have no reels yet.
    final firstWithout = chunks.indexWhere((c) => services.reels.forChunk(c.id).isEmpty);
    final from = (_from ?? (firstWithout < 0 ? 0 : firstWithout)).clamp(0, chunks.length - 1);
    final to = (_to ?? from + 2).clamp(from, chunks.length - 1);
    final sections = chunks.sublist(from, to + 1);
    final mode = services.modes.byId(source.study.modeId);
    final settings = services.settings.settings.generation;
    final types = ReelExchange.typesFor(mode, SubjectProfiles.byId(source.study.subjectId).extraMix, settings);
    final chars = sections.fold<int>(0, (a, c) => a + c.plainText.length) + 4000;
    final theme = Theme.of(context);

    DropdownMenuItem<int> item(int i) => DropdownMenuItem(
      value: i,
      child: Text('§${i + 1} ${chunks[i].title}', overflow: TextOverflow.ellipsis),
    );

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.forum_outlined),
        title: const Text('Generate with your chat subscription'),
        subtitle: const Text('Claude Pro, ChatGPT Plus, Gemini … — no API key needed'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1. Choose sections and copy the prompt.\n'
            '2. Paste it into a new chat (claude.ai, chatgpt.com, gemini.google.com).\n'
            '3. Copy the whole answer and press "Paste answer".',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('from-$from-${chunks.length}'),
                  initialValue: from,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'From section', border: OutlineInputBorder()),
                  items: [for (var i = 0; i < chunks.length; i++) item(i)],
                  onChanged: (v) => setState(() {
                    _from = v;
                    if ((_to ?? 0) < (v ?? 0)) _to = v;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('to-$from-$to-${chunks.length}'),
                  initialValue: to,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'To section', border: OutlineInputBorder()),
                  items: [for (var i = from; i < chunks.length; i++) item(i)],
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${plural(sections.length, 'section')} · ~${(chars / 1000).toStringAsFixed(1)}k characters'
            '${chars > ReelExchange.maxPromptChars ? ' — long; choose fewer sections if the chat refuses' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: chars > ReelExchange.maxPromptChars ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 6),
          Text('Reels per section: $_perSection'),
          Slider(
            value: _perSection.toDouble(),
            min: 2,
            max: 12,
            divisions: 10,
            onChanged: (v) => setState(() => _perSection = v.round()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy prompt'),
                onPressed: () async {
                  final prompt = _exchange.buildPrompt(
                    source: source,
                    sections: sections,
                    mode: mode,
                    settings: settings,
                    types: types,
                    reelsPerSection: _perSection,
                  );
                  await Clipboard.setData(ClipboardData(text: prompt));
                  if (context.mounted) {
                    _snack(
                      context,
                      'Prompt copied (${(prompt.length / 1000).toStringAsFixed(1)}k characters). Paste it into your chat.',
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.content_paste_go),
                label: const Text('Paste answer'),
                onPressed: () => _pasteAnswer(context),
              ),
              TextButton.icon(
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import JSON file'),
                onPressed: () => _importFile(context),
              ),
              TextButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('Export reels'),
                onPressed: () => _export(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pasteAnswer(BuildContext context) async {
    final controller = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null && clip!.text!.contains('"reels"')) controller.text = clip.text!;
    if (!context.mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Paste the chat answer'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 16,
            style: AppTheme.monoStyle.copyWith(fontSize: 12),
            decoration: const InputDecoration(
              hintText: '```json\n{"unrot_reels": 1, "reels": [ … ]}\n```',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Import')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    _import(context, text);
  }

  Future<void> _importFile(BuildContext context) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a reels JSON file',
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
    );
    if (file == null || !context.mounted) return;
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    if (context.mounted) _import(context, text);
  }

  void _import(BuildContext context, String text) {
    final services = context.read<AppServices>();
    final source = services.library.source(widget.sourceId);
    if (source == null) return;
    final report = _exchange.parseAnswer(
      text,
      source: source,
      chunks: services.library.chunks(source.id),
      settings: services.settings.settings.generation,
      existing: services.reels.forSource(source.id),
    );
    services.reels.addAll(report.reels);
    if (report.reels.isNotEmpty) services.feed.refresh();
    final skipped = report.skipped == 0 ? '' : ', ${report.skipped} skipped';
    final problems = report.problems.isEmpty ? '' : ' (${report.problems.first})';
    _snack(context, 'Imported ${report.reels.length} reels$skipped$problems');
  }

  Future<void> _export(BuildContext context) async {
    final services = context.read<AppServices>();
    final source = services.library.source(widget.sourceId);
    if (source == null) return;
    final json = _exchange.exportReels(services.reels.forSource(source.id), services.library.chunks(source.id));
    try {
      final uri = await FilePicker.saveFile(
        fileName: '${source.title.replaceAll(RegExp(r'[^\w-]+'), '_')}_reels.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (uri != null && context.mounted) _snack(context, 'Reels exported.');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: json));
      if (context.mounted) _snack(context, 'Reels copied to the clipboard as JSON.');
    }
  }
}
