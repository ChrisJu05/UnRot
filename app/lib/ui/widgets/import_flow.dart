import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../modules/ingestion/ingestion_service.dart';
import '../../modules/ingestion/text_extractor.dart';

/// Shared UI flows for adding study material.
class ImportFlow {
  static Future<void> pickFiles(BuildContext context) async {
    final services = context.read<AppServices>();
    final exts = services.ingestion.supportedExtensions.toList()..sort();
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        dialogTitle: 'Choose study material',
        type: FileType.custom,
        allowedExtensions: exts,
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not open the file picker: $e');
      return;
    }
    if (files.isEmpty || !context.mounted) return;
    for (final f in files) {
      if (!context.mounted) return;
      await _run(context, f.name, () async => services.ingestion.importFile(await f.readAsBytes(), f.name));
    }
  }

  /// Imports files given as paths (command line / "Open with").
  static Future<void> importPaths(BuildContext context, List<String> paths) async {
    final services = context.read<AppServices>();
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists() || !context.mounted) continue;
      final name = file.uri.pathSegments.last;
      await _run(context, name, () async => services.ingestion.importFile(await file.readAsBytes(), name));
    }
  }

  static Future<void> pasteText(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null && clip!.text!.trim().length > 80) body.text = clip.text!;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste notes or text'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Text (Markdown headings like "# Chapter" create sections)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final services = context.read<AppServices>();
    await _run(
      context,
      title.text.isEmpty ? 'pasted text' : title.text,
      () => services.ingestion.importText(title.text, body.text),
    );
  }

  static Future<void> importSample(BuildContext context) async {
    final services = context.read<AppServices>();
    final text = await rootBundle.loadString('assets/samples/how_learning_works.md');
    if (!context.mounted) return;
    await _run(
      context,
      'sample',
      () => services.ingestion.importText('How Learning Works (sample)', text, format: 'markdown'),
    );
  }

  static Future<void> _run(BuildContext context, String name, Future<ImportResult> Function() job) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 20),
              Expanded(child: Text('Importing $name…\nExtracting text and building sections.')),
            ],
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false);
    try {
      final result = await job();
      if (dialogOpen) navigator.pop();
      final warn = result.warnings.isEmpty ? '' : ' (${result.warnings.join(' ')})';
      messenger.showSnackBar(
        SnackBar(content: Text('Added "${result.source.title}" — ${result.chunks.length} sections$warn')),
      );
      if (context.mounted) context.read<AppServices>().feed.refresh();
    } on ExtractionException catch (e) {
      if (dialogOpen) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (dialogOpen) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Bottom sheet with all add options.
  static Future<void> showAddSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import files'),
            subtitle: const Text('PDF, EPUB, DOCX, Markdown, TXT, HTML'),
            onTap: () {
              Navigator.pop(sheet);
              pickFiles(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Paste text'),
            subtitle: const Text('Lecture notes, articles, anything'),
            onTap: () {
              Navigator.pop(sheet);
              pasteText(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Add sample material'),
            subtitle: const Text('A short text about how learning works'),
            onTap: () {
              Navigator.pop(sheet);
              importSample(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
