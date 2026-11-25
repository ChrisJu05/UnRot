import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../modules/study/progress_tracker.dart';
import '../pen/pen_canvas.dart';
import '../widgets/rich_text.dart';
import 'reel_common.dart';

class FlashcardReel extends StatefulWidget {
  const FlashcardReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<FlashcardReel> createState() => _FlashcardReelState();
}

class _FlashcardReelState extends State<FlashcardReel> {
  bool get flipped => widget.ctx.recall<bool>('flipped') ?? false;
  RecallRating? get rating => widget.ctx.recall<RecallRating>('rating');
  bool _hint = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => widget.ctx.remember('flipped', !flipped)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: flipped ? 1 : 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
            builder: (context, t, _) {
              final showBack = t >= 0.5;
              final angle = t * math.pi;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(angle),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
                  child: _face(showBack ? r.str('back') : r.str('front'), showBack),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (!flipped) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (r.str('hint').isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _hint = true),
                  icon: const Icon(Icons.tips_and_updates_outlined, color: Colors.white70),
                  label: Text(_hint ? r.str('hint') : 'Hint', style: const TextStyle(color: Colors.white70)),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => setState(() => widget.ctx.remember('flipped', true)),
                icon: const Icon(Icons.flip),
                label: const Text('Show answer'),
              ),
            ],
          ),
        ] else
          RatingBar(
            selected: rating,
            onRate: (value) {
              setState(() => widget.ctx.remember('rating', value));
              widget.ctx.onRate(value);
            },
          ),
      ],
    );
  }

  Widget _face(String text, bool back) => Container(
    constraints: const BoxConstraints(minHeight: 240),
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: back ? Colors.white.withValues(alpha: 0.92) : Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          back ? 'ANSWER' : 'TAP TO FLIP',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            color: back ? Colors.black45 : Colors.white54,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        MarkupText(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: back ? 21 : 25,
            fontWeight: FontWeight.w700,
            color: back ? Colors.black87 : Colors.white,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

/// Write or sketch an answer from memory — the pen-first reel type.
class WriteRecallReel extends StatefulWidget {
  const WriteRecallReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<WriteRecallReel> createState() => _WriteRecallReelState();
}

class _WriteRecallReelState extends State<WriteRecallReel> {
  late final PenController _pen;
  late final TextEditingController _text = TextEditingController(text: widget.ctx.recall<String>('typed') ?? '');
  bool get revealed => widget.ctx.recall<bool>('revealed') ?? false;
  bool get typing => widget.ctx.recall<bool>('typing') ?? false;
  RecallRating? get rating => widget.ctx.recall<RecallRating>('rating');

  String get _annotationKey => '${widget.ctx.reel.id}#recall';

  @override
  void initState() {
    super.initState();
    _pen = PenController(
      strokes: widget.ctx.annotations.strokesFor(_annotationKey),
      color: Color(widget.ctx.pen.colorValue),
      width: widget.ctx.pen.baseWidth,
    );
  }

  @override
  void dispose() {
    _pen.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final terms = r.list('key_terms');
    final typed = _text.text.toLowerCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.draw_outlined, color: Colors.white70, size: 18),
            SizedBox(width: 6),
            Text(
              'Write it from memory',
              style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        MarkupText(r.str('prompt'), style: reelTitleStyle.copyWith(fontSize: 22)),
        const SizedBox(height: 14),
        if (!typing)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 260,
              color: Colors.black.withValues(alpha: 0.35),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: PenCanvas(
                      controller: _pen,
                      settings: widget.ctx.pen,
                      onStrokesChanged: () => widget.ctx.annotations.setStrokes(_annotationKey, _pen.strokes),
                      child: const _RuledPaper(),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _pen,
                    builder: (context, _) => _pen.isEmpty
                        ? const IgnorePointer(
                            child: Center(
                              child: Text(
                                '✍️  Write or sketch here\n(pen, finger or mouse)',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38, fontSize: 15),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Positioned(left: 6, bottom: 6, child: PenToolbar(controller: _pen)),
                ],
              ),
            ),
          )
        else
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 7,
            style: const TextStyle(color: Colors.white, fontSize: 17),
            onChanged: (v) => widget.ctx.remember('typed', v),
            decoration: InputDecoration(
              hintText: 'Type your answer…',
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        const SizedBox(height: 10),
        if (!revealed)
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => widget.ctx.remember('typing', !typing)),
                icon: Icon(typing ? Icons.draw_outlined : Icons.keyboard_outlined, color: Colors.white70),
                label: Text(
                  typing ? 'Handwrite instead' : 'Type instead',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => setState(() => widget.ctx.remember('revealed', true)),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Compare'),
              ),
            ],
          )
        else ...[
          GlassPanel(
            color: Colors.white.withValues(alpha: 0.9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MODEL ANSWER',
                  style: TextStyle(fontSize: 12, letterSpacing: 2, color: Colors.black45, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                MarkupText(
                  r.str('model_answer'),
                  style: const TextStyle(fontSize: 17, color: Colors.black87, height: 1.4),
                ),
                if (terms.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in terms)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: typing && typed.contains(t.toLowerCase())
                              ? const Color(0xFFA5D6A7)
                              : const Color(0xFFE0E0E0),
                          label: Text(t, style: const TextStyle(color: Colors.black87)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          RatingBar(
            selected: rating,
            onRate: (value) {
              setState(() => widget.ctx.remember('rating', value));
              widget.ctx.onRate(value);
            },
          ),
        ],
      ],
    );
  }
}

class _RuledPaper extends StatelessWidget {
  const _RuledPaper();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RulePainter(), child: const SizedBox.expand());
}

class _RulePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var y = 36.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
