import 'package:material_ui/material_ui.dart';

import '../../core/models/chunk.dart';
import '../../core/models/source.dart';
import '../../modules/reels/reel_types.dart';
import '../theme/app_theme.dart';
import 'question_reels.dart';
import 'recall_reels.dart';
import 'reel_common.dart';
import 'teaching_reels.dart';
import 'visual_reel.dart';

typedef ReelBodyBuilder = Widget Function(ReelContext ctx);

/// Maps reel type ids to widgets. Register widgets for new reel types here.
class ReelWidgets {
  static final Map<String, ReelBodyBuilder> builders = {
    'explainer': (c) => ExplainerReel(c),
    'key_points': (c) => KeyPointsReel(c),
    'mnemonic': (c) => MnemonicReel(c),
    'quiz': (c) => QuizReel(c),
    'true_false': (c) => TrueFalseReel(c),
    'cloze': (c) => ClozeReel(c),
    'flashcard': (c) => FlashcardReel(c),
    'write_recall': (c) => WriteRecallReel(c),
    'visual': (c) => VisualReel(c),
  };

  static Widget body(ReelContext ctx) {
    final builder = builders[ctx.reel.type];
    if (builder == null) {
      return Text('Unsupported reel type "${ctx.reel.type}"', style: reelBodyStyle);
    }
    // Keyed by reel so state is never reused for a different reel.
    return KeyedSubtree(key: ValueKey('body-${ctx.reel.id}'), child: builder(ctx));
  }
}

/// Full-screen reel: gradient background, header, auto-fitting body and footer.
class ReelPage extends StatelessWidget {
  const ReelPage({
    super.key,
    required this.ctx,
    required this.source,
    required this.chunk,
    required this.isReview,
    this.rightInset = 0,
    this.overlay,
  });

  final ReelContext ctx;
  final StudySource? source;
  final SourceChunk? chunk;
  final bool isReview;

  /// Space reserved on the right for the action rail.
  final double rightInset;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final reel = ctx.reel;
    final spec = ReelTypes.byId(reel.type);
    final colors = AppTheme.gradientFor('${reel.chunkId}/${reel.type}');
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22 + rightInset, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _chip(AppTheme.reelIcons[reel.type] ?? Icons.auto_awesome, spec?.label ?? reel.type),
                      if (isReview) ...[
                        const SizedBox(width: 8),
                        _chip(Icons.replay, 'Review', color: const Color(0xFFFFB74D)),
                      ],
                      if (reel.parentReelId != null) ...[
                        const SizedBox(width: 8),
                        _chip(Icons.unfold_more, 'Deep dive'),
                      ],
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: ReelWidgets.body(ctx),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _footer(),
                ],
              ),
            ),
            if (overlay != null) Positioned.fill(child: overlay!),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? Colors.white),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _footer() {
    final title = source?.title ?? 'Unknown source';
    final section = chunk == null ? '' : chunk!.breadcrumb;
    final count = source?.chunkCount ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Icon(Icons.menu_book_outlined, size: 18, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              if (section.isNotEmpty)
                Text(
                  chunk != null && count > 0 ? '§${chunk!.index + 1}/$count · $section' : section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
