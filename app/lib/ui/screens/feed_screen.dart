import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../core/storage/repositories.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/models/reel.dart';
import '../../modules/feed/feed_engine.dart';
import '../../modules/study/progress_tracker.dart';
import '../pen/pen_canvas.dart';
import '../reels/reel_common.dart';
import '../reels/reel_widgets.dart';
import '../widgets/import_flow.dart';
import 'source_detail_screen.dart';

/// The vertical, TikTok-style reel feed.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.onOpenLibrary, this.onOpenSettings});

  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenSettings;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final PageController _pages;
  final FocusNode _focus = FocusNode(debugLabel: 'feed');
  final Map<String, Object?> _memory = {};
  bool _annotating = false;
  PenController? _annotationPen;
  DateTime _lastWheel = DateTime(2000);

  FeedEngine get _feed => context.read<AppServices>().feed;

  @override
  void initState() {
    super.initState();
    final feed = context.read<AppServices>().feed;
    _pages = PageController(initialPage: feed.currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await feed.ensureBuffer(force: feed.items.isEmpty);
      if (mounted && feed.items.isNotEmpty) feed.onPageChanged(feed.currentIndex);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _focus.dispose();
    _annotationPen?.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (_annotating || !_pages.hasClients) return;
    final target = (_feed.currentIndex + delta).clamp(0, _feed.items.length);
    _pages.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.keyJ) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.keyK) {
      _go(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _annotating) return;
    // Claim the wheel event before the PageView so one notch = one reel.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final now = DateTime.now();
      if (now.difference(_lastWheel).inMilliseconds < 350) return;
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      if (dy.abs() < 4) return;
      _lastWheel = now;
      _go(dy > 0 ? 1 : -1);
    });
  }

  void _toggleAnnotate(Reel reel) {
    final services = context.read<AppServices>();
    setState(() {
      if (_annotating) {
        services.annotations.setStrokes(reel.id, _annotationPen?.strokes ?? const []);
        _annotationPen?.dispose();
        _annotationPen = null;
        _annotating = false;
      } else {
        final pen = services.settings.settings.pen;
        _annotationPen = PenController(
          strokes: services.annotations.strokesFor(reel.id),
          color: Color(pen.colorValue),
          width: pen.baseWidth,
        );
        _annotating = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final feed = context.watch<FeedEngine>();
    context.watch<SettingsRepository>();
    context.watch<AnnotationRepository>();
    final penSettings = services.settings.settings.pen;
    final dragDevices = <PointerDeviceKind>{
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      if (!penSettings.stylusDrawsOnReels) PointerDeviceKind.stylus,
    };

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final reelWidth = wide ? (constraints.maxHeight * 0.62).clamp(380.0, 560.0) : constraints.maxWidth;
          final current = feed.current;

          final pageView = ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: dragDevices, scrollbars: false),
            child: PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              physics: _annotating ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: feed.items.length + 1,
              onPageChanged: (i) {
                if (_annotating && current != null) _toggleAnnotate(current.reel);
                feed.onPageChanged(i);
              },
              itemBuilder: (context, index) {
                final Widget page = index >= feed.items.length
                    ? _StatusPage(
                        feed: feed,
                        onOpenLibrary: widget.onOpenLibrary,
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : _buildReel(feed.items[index], wide, penSettings.stylusDrawsOnReels, index == feed.currentIndex);
                return Listener(onPointerSignal: _onPointerSignal, child: page);
              },
            ),
          );

          final rail = current == null
              ? const SizedBox.shrink()
              : _ActionRail(
                  reel: current.reel,
                  annotating: _annotating,
                  onAnnotate: () => _toggleAnnotate(current.reel),
                  onExplainMore: () => _explainMore(current.reel),
                );

          return Stack(
            children: [
              if (wide)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: reelWidth,
                      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: pageView),
                    ),
                    SizedBox(
                      width: 84,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(padding: const EdgeInsets.only(bottom: 90), child: rail),
                      ),
                    ),
                  ],
                )
              else ...[
                Positioned.fill(child: pageView),
                Positioned(right: 6, bottom: 96, child: rail),
              ],
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: _TopBar(feed: feed)),
              ),
              if (_annotating && _annotationPen != null)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: PenToolbar(controller: _annotationPen!, onDone: () => _toggleAnnotate(current!.reel)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReel(FeedItem item, bool wide, bool stylusDraws, bool isCurrent) {
    final services = context.read<AppServices>();
    final reel = item.reel;
    final ctx = ReelContext(
      reel: reel,
      pen: services.settings.settings.pen,
      annotations: services.annotations,
      memory: _memory,
      onAnswer: (correct) => services.tracker.recordAnswer(reel, correct, DateTime.now()),
      onRate: (rating) => services.tracker.recordRating(reel, rating, DateTime.now()),
      imageFile: services.sourceImage,
      allowWebImages: services.settings.settings.generation.allowWebImages,
    );
    Widget? overlay;
    if (_annotating && isCurrent && _annotationPen != null) {
      overlay = PenCanvas(controller: _annotationPen!, settings: services.settings.settings.pen);
    } else if (stylusDraws || services.annotations.strokesFor(reel.id).isNotEmpty) {
      overlay = _PassiveAnnotations(reel: reel, stylusDraws: stylusDraws);
    }
    return ReelPage(
      key: ValueKey(reel.id),
      ctx: ctx,
      source: services.library.source(reel.sourceId),
      chunk: services.library.chunk(reel.chunkId),
      isReview: item.isReview,
      rightInset: wide ? 0 : 58,
      overlay: overlay,
    );
  }

  Future<void> _explainMore(Reel reel) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Creating a deep dive…'), duration: Duration(seconds: 2)));
    final before = _feed.items.length;
    await _feed.explainMore(reel);
    if (!mounted) return;
    if (_feed.items.length > before) {
      _go(1);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(_feed.lastError ?? 'Nothing new to add for this reel — try another one.')),
      );
    }
  }
}

/// Shows saved annotations and lets a stylus draw directly on a reel.
class _PassiveAnnotations extends StatefulWidget {
  const _PassiveAnnotations({required this.reel, required this.stylusDraws});
  final Reel reel;
  final bool stylusDraws;

  @override
  State<_PassiveAnnotations> createState() => _PassiveAnnotationsState();
}

class _PassiveAnnotationsState extends State<_PassiveAnnotations> {
  late final PenController _pen;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    final pen = services.settings.settings.pen;
    _pen = PenController(
      strokes: services.annotations.strokesFor(widget.reel.id),
      color: Color(pen.colorValue),
      width: pen.baseWidth,
    );
  }

  @override
  void dispose() {
    _pen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return PenCanvas(
      controller: _pen,
      settings: services.settings.settings.pen,
      enabled: widget.stylusDraws,
      acceptFingersAndMouse: false,
      onStrokesChanged: () => services.annotations.setStrokes(widget.reel.id, _pen.strokes),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.reel,
    required this.annotating,
    required this.onAnnotate,
    required this.onExplainMore,
  });

  final Reel reel;
  final bool annotating;
  final VoidCallback onAnnotate;
  final VoidCallback onExplainMore;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final state = context.watch<ProgressRepository>().peekReel(reel.id);
    void feedback(ReelFeedback f, String message) {
      services.tracker.recordFeedback(reel, f);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: state?.bookmarked == true ? Icons.bookmark : Icons.bookmark_border,
          label: 'Save',
          active: state?.bookmarked == true,
          onTap: () => services.tracker.toggleBookmark(reel),
        ),
        _RailButton(
          icon: Icons.thumb_up_alt_outlined,
          label: 'Got it',
          onTap: () => feedback(ReelFeedback.gotIt, 'Nice! Marked as understood.'),
        ),
        _RailButton(
          icon: Icons.help_outline,
          label: 'Confusing',
          onTap: () => feedback(ReelFeedback.confusing, "Got it — upcoming reels for this section will be simpler."),
        ),
        _RailButton(
          icon: Icons.fast_forward_outlined,
          label: 'Too easy',
          onTap: () => feedback(ReelFeedback.tooEasy, 'Okay — upcoming reels for this section will be harder.'),
        ),
        _RailButton(icon: Icons.unfold_more, label: 'Explain\nmore', onTap: onExplainMore),
        _RailButton(
          icon: annotating ? Icons.edit_off : Icons.edit_outlined,
          label: annotating ? 'Done' : 'Draw',
          active: annotating,
          onTap: onAnnotate,
        ),
        _RailButton(
          icon: Icons.menu_book_outlined,
          label: 'Source',
          onTap: () {
            final source = services.library.source(reel.sourceId);
            if (source != null) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => SourceDetailScreen(sourceId: source.id)));
            }
          },
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? const Color(0xFFFFD54F) : Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: active ? Colors.black : Colors.white, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4)],
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.feed});
  final FeedEngine feed;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final settings = context.watch<SettingsRepository>().settings;
    final focusSource = settings.feed.focusSourceId == null
        ? null
        : services.library.source(settings.feed.focusSourceId!);
    final focusChunk = feed.focusChunkId == null ? null : services.library.chunk(feed.focusChunkId!);
    String? focusLabel;
    VoidCallback? clearFocus;
    if (focusChunk != null) {
      focusLabel = 'Section: ${focusChunk.title}';
      clearFocus = () => feed.setFocusChunk(null);
    } else if (focusSource != null) {
      focusLabel = focusSource.title;
      clearFocus = () {
        services.settings.update((s) => s.feed.focusSourceId = null);
        feed.refresh();
      };
    }
    return IgnorePointer(
      ignoring: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(
          children: [
            const Text(
              'UnRot',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            if (focusLabel != null)
              Flexible(
                child: InputChip(
                  avatar: const Icon(Icons.center_focus_strong, size: 16),
                  label: Text(focusLabel, overflow: TextOverflow.ellipsis),
                  onDeleted: clearFocus,
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              Text(
                services.generation.usesOffline ? 'For you · offline' : 'For you',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6)],
                ),
              ),
            const Spacer(),
            if (feed.isGenerating)
              Tooltip(
                message: 'Creating reels${feed.generatingLabel != null ? ' for ${feed.generatingLabel}' : ''}…',
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            if (feed.lastError != null && !feed.isGenerating)
              IconButton(
                tooltip: feed.lastError,
                icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D)),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(feed.lastError!),
                    action: SnackBarAction(label: 'Retry', onPressed: feed.retry),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.feed, this.onOpenLibrary, this.onOpenSettings});
  final FeedEngine feed;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (feed.isGenerating) {
      content = _message(
        icon: const SizedBox(width: 46, height: 46, child: CircularProgressIndicator(color: Colors.white)),
        title: 'Creating your reels…',
        text: feed.generatingLabel == null ? '' : 'Section: ${feed.generatingLabel}',
      );
    } else if (feed.emptyReason == 'no_sources') {
      content = _message(
        icon: const Text('📚', style: TextStyle(fontSize: 64)),
        title: 'Add your study material',
        text: 'Import scripts, books or notes (PDF, EPUB, DOCX, Markdown, TXT). UnRot turns them into bite-sized, interactive reels.',
        actions: [
          FilledButton.icon(
            onPressed: () => ImportFlow.pickFiles(context),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import files'),
          ),
          OutlinedButton.icon(
            onPressed: () => ImportFlow.pasteText(context),
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste text'),
          ),
          TextButton(onPressed: () => ImportFlow.importSample(context), child: const Text('Try with sample material')),
        ],
      );
    } else if (feed.emptyReason == 'no_active_sources') {
      content = _message(
        icon: const Icon(Icons.visibility_off_outlined, size: 56, color: Colors.white),
        title: 'No sources in your feed',
        text: 'All sources are hidden from the feed. Enable "Show in feed" for at least one source.',
        actions: [FilledButton(onPressed: onOpenLibrary, child: const Text('Open library'))],
      );
    } else if (feed.lastError != null) {
      content = _message(
        icon: const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.white),
        title: 'Could not create reels',
        text: feed.lastError!,
        actions: [
          FilledButton.icon(onPressed: feed.retry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          OutlinedButton(onPressed: onOpenSettings, child: const Text('AI settings')),
        ],
      );
    } else if (feed.emptyReason == 'nothing_to_show') {
      content = _message(
        icon: const Text('🎉', style: TextStyle(fontSize: 64)),
        title: 'All caught up!',
        text: 'You have worked through everything that is due. Add more material or switch a source to another study mode.',
        actions: [FilledButton(onPressed: onOpenLibrary, child: const Text('Open library'))],
      );
    } else {
      content = _message(
        icon: const SizedBox(width: 46, height: 46, child: CircularProgressIndicator(color: Colors.white)),
        title: 'Loading…',
        text: '',
      );
      // Make sure something is happening.
      scheduleMicrotask(() => feed.ensureBuffer(force: true));
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: Center(
        child: Padding(padding: const EdgeInsets.all(28), child: content),
      ),
    );
  }

  Widget _message({
    required Widget icon,
    required String title,
    required String text,
    List<Widget> actions = const [],
  }) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 440),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: actions),
        ],
      ],
    ),
  );
}
