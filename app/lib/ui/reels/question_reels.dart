import 'package:material_ui/material_ui.dart';

import '../../core/util/json.dart';
import '../widgets/rich_text.dart';
import 'reel_common.dart';

class QuizReel extends StatefulWidget {
  const QuizReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<QuizReel> createState() => _QuizReelState();
}

class _QuizReelState extends State<QuizReel> {
  int? get selected => widget.ctx.recall<int>('selected');

  void _choose(int index) {
    if (selected != null) return;
    final correct = index == jInt(widget.ctx.reel.data['answer_index']);
    setState(() => widget.ctx.remember('selected', index));
    widget.ctx.onAnswer(correct);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final options = r.list('options');
    final answer = jInt(r.data['answer_index']);
    final sel = selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkupText(r.str('question'), style: reelTitleStyle.copyWith(fontSize: 24)),
        const SizedBox(height: 20),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionButton(
              label: options[i],
              letter: String.fromCharCode(65 + i),
              state: sel == null
                  ? _OptionState.idle
                  : (i == answer ? _OptionState.correct : (i == sel ? _OptionState.wrong : _OptionState.dimmed)),
              onTap: () => _choose(i),
            ),
          ),
        if (sel != null) ...[
          const SizedBox(height: 8),
          AnswerFeedback(correct: sel == answer, explanation: r.str('explanation')),
        ],
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.letter, required this.state, required this.onTap});
  final String label;
  final String letter;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _OptionState.idle => Colors.white.withValues(alpha: 0.14),
      _OptionState.correct => const Color(0xFF2E7D32),
      _OptionState.wrong => const Color(0xFFC62828),
      _OptionState.dimmed => Colors.white.withValues(alpha: 0.06),
    };
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: state == _OptionState.idle ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  letter,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MarkupText(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    color: state == _OptionState.dimmed ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (state == _OptionState.correct) const Icon(Icons.check, color: Colors.white),
              if (state == _OptionState.wrong) const Icon(Icons.close, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class TrueFalseReel extends StatefulWidget {
  const TrueFalseReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<TrueFalseReel> createState() => _TrueFalseReelState();
}

class _TrueFalseReelState extends State<TrueFalseReel> {
  bool? get choice => widget.ctx.recall<bool>('choice');

  void _choose(bool value) {
    if (choice != null) return;
    setState(() => widget.ctx.remember('choice', value));
    widget.ctx.onAnswer(value == (widget.ctx.reel.data['answer'] == true));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final answer = r.data['answer'] == true;
    final c = choice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'True or false?',
          style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        GlassPanel(child: MarkupText(r.str('statement'), style: reelTitleStyle.copyWith(fontSize: 23))),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _bigButton(
                'True',
                Icons.check,
                const Color(0xFF2E7D32),
                c == null ? () => _choose(true) : null,
                highlight: c != null && answer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _bigButton(
                'False',
                Icons.close,
                const Color(0xFFC62828),
                c == null ? () => _choose(false) : null,
                highlight: c != null && !answer,
              ),
            ),
          ],
        ),
        if (c != null) ...[
          const SizedBox(height: 16),
          AnswerFeedback(
            correct: c == answer,
            explanation: r.str('explanation'),
            correctAnswer: answer ? 'True' : 'False',
          ),
        ],
      ],
    );
  }

  Widget _bigButton(String label, IconData icon, Color color, VoidCallback? onTap, {required bool highlight}) =>
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: onTap == null && !highlight ? 0.25 : 0.9),
          disabledBackgroundColor: color.withValues(alpha: highlight ? 0.9 : 0.2),
          disabledForegroundColor: Colors.white,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 58),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

class ClozeReel extends StatefulWidget {
  const ClozeReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<ClozeReel> createState() => _ClozeReelState();
}

class _ClozeReelState extends State<ClozeReel> {
  late final TextEditingController _controller = TextEditingController(text: widget.ctx.recall<String>('typed') ?? '');
  bool? get result => widget.ctx.recall<bool>('result');
  bool _showHint = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check({bool reveal = false}) {
    if (result != null) return;
    final correct = !reveal && answersMatch(_controller.text, widget.ctx.reel.str('answer'));
    setState(() {
      widget.ctx.remember('typed', _controller.text);
      widget.ctx.remember('result', correct);
    });
    widget.ctx.onAnswer(correct);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final parts = r.str('text').split('____');
    final res = result;
    final answer = r.str('answer');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fill the gap',
          style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: reelTitleStyle.copyWith(fontSize: 23, fontWeight: FontWeight.w700),
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                ...MarkupText.spans(parts[i], reelTitleStyle),
                if (i < parts.length - 1)
                  TextSpan(
                    text: res == null ? '  ______  ' : ' $answer ',
                    style: TextStyle(
                      color: res == null ? Colors.white : (res ? const Color(0xFFA5D6A7) : const Color(0xFFFFCC80)),
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (res == null) ...[
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              hintText: 'Type the missing word…',
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (r.str('hint').isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _showHint = true),
                  icon: const Icon(Icons.tips_and_updates_outlined, color: Colors.white70),
                  label: Text(_showHint ? r.str('hint') : 'Hint', style: const TextStyle(color: Colors.white70)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => _check(reveal: true),
                child: const Text('Reveal', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _check, child: const Text('Check')),
            ],
          ),
        ] else
          AnswerFeedback(correct: res, correctAnswer: answer),
      ],
    );
  }
}
