import 'package:material_ui/material_ui.dart';

import '../widgets/rich_text.dart';
import 'reel_common.dart';

class ExplainerReel extends StatelessWidget {
  const ExplainerReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  Widget build(BuildContext context) {
    final r = ctx.reel;
    final emoji = r.str('emoji');
    final takeaway = r.str('takeaway');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (emoji.isNotEmpty) Text(emoji, style: const TextStyle(fontSize: 56)),
        if (r.str('title').isNotEmpty) ...[
          const SizedBox(height: 8),
          MarkupText(r.str('title'), style: reelTitleStyle),
        ],
        const SizedBox(height: 16),
        MarkupText(r.str('body'), style: reelBodyStyle),
        if (takeaway.isNotEmpty) ...[
          const SizedBox(height: 22),
          GlassPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt, color: Color(0xFFFFE082)),
                const SizedBox(width: 10),
                Expanded(
                  child: MarkupText(
                    takeaway,
                    style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class KeyPointsReel extends StatelessWidget {
  const KeyPointsReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  Widget build(BuildContext context) {
    final r = ctx.reel;
    final points = r.list('points');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (r.str('emoji').isNotEmpty) Text('${r.str('emoji')} ', style: const TextStyle(fontSize: 34)),
            Expanded(child: MarkupText(r.str('title'), style: reelTitleStyle.copyWith(fontSize: 25))),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < points.length; i++)
          TweenAnimationBuilder<double>(
            key: ValueKey('${r.id}-$i'),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 350 + i * 220),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: MarkupText(points[i], style: reelBodyStyle.copyWith(fontSize: 18))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class MnemonicReel extends StatelessWidget {
  const MnemonicReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  Widget build(BuildContext context) {
    final r = ctx.reel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🧠  Memory hook',
          style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        MarkupText(r.str('concept'), style: reelTitleStyle.copyWith(fontSize: 24)),
        const SizedBox(height: 18),
        GlassPanel(
          color: Colors.white.withValues(alpha: 0.14),
          child: MarkupText(
            r.str('hook'),
            style: const TextStyle(fontSize: 24, color: Color(0xFFFFE082), fontWeight: FontWeight.w800, height: 1.35),
          ),
        ),
        if (r.str('explanation').isNotEmpty) ...[
          const SizedBox(height: 16),
          MarkupText(r.str('explanation'), style: reelBodyStyle.copyWith(fontSize: 18)),
        ],
      ],
    );
  }
}
