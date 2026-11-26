import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/util/json.dart';
import '../../modules/reels/reel_types.dart';
import '../../modules/study/progress_tracker.dart';
import '../../modules/visuals/expression.dart';
import '../visuals/math_text.dart';
import '../widgets/rich_text.dart';
import 'reel_common.dart';

const _accent = Color(0xFFFFD54F);
const _sectionStyle = TextStyle(fontSize: 13, letterSpacing: 1.6, color: Colors.white60, fontWeight: FontWeight.w800);

/// Formats numbers for exercises: 0.00123 -> "1.23·10⁻³".
String formatScientific(double v, {int digits = 4}) {
  if (!v.isFinite) return formatNumber(v);
  final a = v.abs();
  if (a == 0 || (a >= 1e-3 && a < 1e5)) return formatNumber(v, decimals: digits);
  final exp = (math.log(a) / math.ln10).floor();
  final mantissa = v / math.pow(10, exp);
  const sup = {
    '-': '⁻',
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
  };
  final e = exp.toString().split('').map((c) => sup[c] ?? c).join();
  return '${formatNumber(mantissa, decimals: 3)}·10$e';
}

Widget _numberedStep(int n, Widget child, {Color? color}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color ?? Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Text(
          '$n',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: child),
    ],
  ),
);

Widget _revealButton(String label, VoidCallback onTap, {IconData icon = Icons.navigate_next}) => Align(
  alignment: Alignment.centerRight,
  child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
);

/// Step-by-step recipe ("Rechenrezept") revealed one step at a time, then a worked example.
class MathRecipeReel extends StatefulWidget {
  const MathRecipeReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<MathRecipeReel> createState() => _MathRecipeReelState();
}

class _MathRecipeReelState extends State<MathRecipeReel> {
  int get _shown => widget.ctx.recall<int>('steps') ?? 1;
  int get _exampleShown => widget.ctx.recall<int>('example') ?? 0;

  void _set(String key, int value) => setState(() => widget.ctx.remember(key, value));

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final steps = [for (final s in (r.data['steps'] as List? ?? const [])) jMap(s)];
    final example = jMap(r.data['example']);
    final exampleSteps = jStringList(example['steps']);
    final pitfalls = r.list('pitfalls');
    final shown = _shown.clamp(1, steps.length);
    final allSteps = shown >= steps.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('🧮  RECIPE', style: _sectionStyle),
        const SizedBox(height: 6),
        MarkupText(r.str('title'), style: reelTitleStyle.copyWith(fontSize: 24)),
        if (r.str('goal').isNotEmpty) ...[
          const SizedBox(height: 8),
          MarkupText('**Goal:** ${r.str('goal')}', style: reelSmallStyle.copyWith(color: Colors.white)),
        ],
        if (r.str('when_to_use').isNotEmpty)
          MarkupText('**When:** ${r.str('when_to_use')}', style: reelSmallStyle.copyWith(color: Colors.white)),
        const SizedBox(height: 14),
        for (var i = 0; i < shown; i++)
          _numberedStep(
            i + 1,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkupText(jString(steps[i]['action']), style: reelBodyStyle.copyWith(fontSize: 17)),
                if (jString(steps[i]['latex']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: MathTex(
                      jString(steps[i]['latex']),
                      style: const TextStyle(color: _accent, fontSize: 19),
                      display: true,
                    ),
                  ),
              ],
            ),
            color: _accent.withValues(alpha: 0.35),
          ),
        if (!allSteps)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _set('steps', steps.length),
                child: const Text('Show all', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: () => _set('steps', shown + 1),
                icon: const Icon(Icons.navigate_next),
                label: Text('Step ${shown + 1} of ${steps.length}'),
              ),
            ],
          ),
        if (allSteps && jString(example['problem']).isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_exampleShown == 0)
            _revealButton('Worked example', () => _set('example', 1), icon: Icons.play_arrow)
          else
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WORKED EXAMPLE', style: _sectionStyle),
                  const SizedBox(height: 6),
                  MarkupText(jString(example['problem']), style: reelBodyStyle.copyWith(fontSize: 16)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < math.min(_exampleShown, exampleSteps.length); i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: MarkupText('→ ${exampleSteps[i]}', style: reelSmallStyle.copyWith(color: Colors.white)),
                    ),
                  if (_exampleShown < exampleSteps.length)
                    _revealButton('Next', () => _set('example', _exampleShown + 1))
                  else if (jString(example['result']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: MarkupText(
                        '**Result:** ${jString(example['result'])}',
                        style: const TextStyle(color: _accent, fontSize: 17),
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (allSteps && pitfalls.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final p in pitfalls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: MarkupText('⚠️ $p', style: reelSmallStyle.copyWith(color: const Color(0xFFFFCC80))),
            ),
        ],
      ],
    );
  }
}

/// Theorem ("Satz"): assumptions shown, statement recalled first, then explanation and self-rating.
class TheoremReel extends StatefulWidget {
  const TheoremReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<TheoremReel> createState() => _TheoremReelState();
}

class _TheoremReelState extends State<TheoremReel> {
  bool get _revealed => widget.ctx.recall<bool>('revealed') ?? false;
  String? get _open => widget.ctx.recall<String>('open');
  RecallRating? get _rating => widget.ctx.recall<RecallRating>('rating');

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final assumptions = r.list('assumptions');
    final extras = {
      'intuition': ('💡 Intuition', r.str('intuition')),
      'proof_idea': ('🧩 Proof idea', r.str('proof_idea')),
      'example': ('🔢 Example', r.str('example')),
    }..removeWhere((_, v) => v.$2.isEmpty);
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _accent, width: 4)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.str('kind').toUpperCase(), style: _sectionStyle.copyWith(color: _accent)),
          const SizedBox(height: 4),
          MarkupText(r.str('name'), style: reelTitleStyle.copyWith(fontSize: 24)),
          if (assumptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('ASSUMPTIONS', style: _sectionStyle),
            const SizedBox(height: 4),
            for (final a in assumptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: MarkupText('• $a', style: reelSmallStyle.copyWith(color: Colors.white, fontSize: 16)),
              ),
          ],
          const SizedBox(height: 12),
          if (!_revealed)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => widget.ctx.remember('revealed', true)),
              child: GlassPanel(
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined, color: Colors.white70),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recall the statement in your head, then tap to reveal it.',
                        style: reelSmallStyle.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const Text('STATEMENT', style: _sectionStyle),
            const SizedBox(height: 4),
            if (r.str('statement').isNotEmpty)
              MarkupText(r.str('statement'), style: reelBodyStyle.copyWith(fontSize: 18)),
            if (r.str('formula').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: MathTex(
                    r.str('formula'),
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                    display: true,
                  ),
                ),
              ),
            if (extras.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in extras.entries)
                    ChoiceChip(
                      label: Text(e.value.$1),
                      selected: _open == e.key,
                      onSelected: (v) => setState(() => widget.ctx.remember('open', v ? e.key : null)),
                    ),
                ],
              ),
            if (_open != null && extras[_open] != null) ...[
              const SizedBox(height: 8),
              GlassPanel(
                child: MarkupText(extras[_open]!.$2, style: reelSmallStyle.copyWith(color: Colors.white, fontSize: 16)),
              ),
            ],
            const SizedBox(height: 12),
            RatingBar(
              selected: _rating,
              onRate: (v) {
                setState(() => widget.ctx.remember('rating', v));
                widget.ctx.onRate(v);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Formula card: formula plus symbol legend; meanings are recalled by tapping.
class FormulaReel extends StatefulWidget {
  const FormulaReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<FormulaReel> createState() => _FormulaReelState();
}

class _FormulaReelState extends State<FormulaReel> {
  Set<int> get _shown => widget.ctx.recall<Set<int>>('shown') ?? <int>{};
  RecallRating? get _rating => widget.ctx.recall<RecallRating>('rating');

  void _reveal(Iterable<int> indexes) => setState(() => widget.ctx.remember('shown', {..._shown, ...indexes}));

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final symbols = [for (final s in (r.data['symbols'] as List? ?? const [])) jMap(s)];
    final shown = _shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('📐  FORMULA', style: _sectionStyle),
        if (r.str('name').isNotEmpty) ...[
          const SizedBox(height: 4),
          MarkupText(r.str('name'), style: reelTitleStyle.copyWith(fontSize: 24)),
        ],
        const SizedBox(height: 14),
        GlassPanel(
          child: Center(
            child: MathTex(r.str('latex'), style: const TextStyle(color: Colors.white, fontSize: 28), display: true),
          ),
        ),
        if (r.str('conditions').isNotEmpty) ...[
          const SizedBox(height: 8),
          MarkupText('**Valid if:** ${r.str('conditions')}', style: reelSmallStyle.copyWith(color: Colors.white)),
        ],
        if (symbols.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('WHAT DOES EACH SYMBOL MEAN?', style: _sectionStyle)),
              if (shown.length < symbols.length)
                TextButton(
                  onPressed: () => _reveal(List.generate(symbols.length, (i) => i)),
                  child: const Text('Reveal all', style: TextStyle(color: Colors.white70)),
                ),
            ],
          ),
          for (var i = 0; i < symbols.length; i++)
            InkWell(
              onTap: () => _reveal([i]),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: MathTex(
                        jString(symbols[i]['symbol']),
                        style: const TextStyle(color: _accent, fontSize: 20),
                      ),
                    ),
                    Expanded(
                      child: shown.contains(i)
                          ? MarkupText(
                              jString(symbols[i]['meaning']),
                              style: reelSmallStyle.copyWith(color: Colors.white, fontSize: 16),
                            )
                          : const Text(
                              'tap to reveal',
                              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
                            ),
                    ),
                    if (shown.contains(i) && jString(symbols[i]['unit']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('[${unitLabel(jString(symbols[i]['unit']))}]', style: reelSmallStyle),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (r.str('intuition').isNotEmpty && shown.length >= symbols.length) ...[
          const SizedBox(height: 8),
          MarkupText('💡 ${r.str('intuition')}', style: reelSmallStyle.copyWith(color: Colors.white, fontSize: 16)),
        ],
        if (shown.isNotEmpty || symbols.isEmpty) ...[
          const SizedBox(height: 12),
          RatingBar(
            selected: _rating,
            onRate: (v) {
              setState(() => widget.ctx.remember('rating', v));
              widget.ctx.onRate(v);
            },
          ),
        ],
      ],
    );
  }
}

/// Numeric exercise: the answer (number or expression) is checked within a relative tolerance.
class CalcExerciseReel extends StatefulWidget {
  const CalcExerciseReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<CalcExerciseReel> createState() => _CalcExerciseReelState();
}

class _CalcExerciseReelState extends State<CalcExerciseReel> {
  late final TextEditingController _input = TextEditingController(text: widget.ctx.recall<String>('typed') ?? '');
  bool? get _result => widget.ctx.recall<bool>('result');
  bool get _solution => widget.ctx.recall<bool>('solution') ?? false;
  bool _hint = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  static bool isCorrect(double given, double expected, double tolerance) {
    if (expected == 0) return given.abs() <= tolerance;
    return ((given - expected) / expected).abs() <= tolerance;
  }

  void _check() {
    final value = parseNumber(_input.text);
    if (value == null) {
      setState(() => _error = 'Enter a number, e.g. 1.5e-3 or 2*pi*50');
      return;
    }
    final r = widget.ctx.reel;
    final correct = isCorrect(value, jDouble(r.data['answer']), jDouble(r.data['tolerance'], 0.02));
    setState(() {
      _error = null;
      widget.ctx.remember('typed', _input.text);
      if (_result == null) {
        widget.ctx.remember('result', correct);
        widget.ctx.onAnswer(correct);
      }
      if (!correct) widget.ctx.remember('solution', true);
    });
  }

  void _showSolution() {
    setState(() {
      if (_result == null) {
        widget.ctx.remember('result', false);
        widget.ctx.onAnswer(false);
      }
      widget.ctx.remember('solution', true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ctx.reel;
    final given = [for (final g in (r.data['given'] as List? ?? const [])) jMap(g)];
    final answer = jDouble(r.data['answer']);
    final unit = unitLabel(r.str('unit'));
    final result = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✏️  CALCULATE', style: _sectionStyle),
        const SizedBox(height: 6),
        MarkupText(r.str('problem'), style: reelBodyStyle.copyWith(fontSize: 18)),
        if (given.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GIVEN', style: _sectionStyle),
                const SizedBox(height: 4),
                for (final g in given)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        MathTex(jString(g['symbol']), style: const TextStyle(color: _accent, fontSize: 18)),
                        const Text('  =  ', style: TextStyle(color: Colors.white70)),
                        Flexible(
                          child: Text(
                            '${parseNumber(g['value']) != null ? formatScientific(parseNumber(g['value'])!) : jString(g['value'])} ${unitLabel(jString(g['unit']))}',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (r.str('asked').isNotEmpty) ...[
          const SizedBox(height: 10),
          MarkupText('**Find:** ${r.str('asked')}', style: reelBodyStyle.copyWith(fontSize: 17)),
        ],
        const SizedBox(height: 12),
        if (result == null) ...[
          TextField(
            controller: _input,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(color: Colors.white, fontSize: 18),
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              hintText: 'Your result',
              suffixText: unit,
              errorText: _error,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (r.str('hint').isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _hint = true),
                  icon: const Icon(Icons.tips_and_updates_outlined, color: Colors.white70),
                  label: const Text('Hint', style: TextStyle(color: Colors.white70)),
                ),
              const Spacer(),
              TextButton(
                onPressed: _showSolution,
                child: const Text('Solution', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 6),
              FilledButton(onPressed: _check, child: const Text('Check')),
            ],
          ),
          if (_hint) MarkupText('💡 ${r.str('hint')}', style: reelSmallStyle.copyWith(color: Colors.white)),
        ] else
          AnswerFeedback(
            correct: result,
            correctAnswer: '${formatScientific(answer)} $unit'.trim(),
            explanation: result ? 'Expected ${formatScientific(answer)} $unit'.trim() : '',
          ),
        if (_solution || result != null) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SOLUTION', style: _sectionStyle),
                const SizedBox(height: 6),
                for (var i = 0; i < r.list('solution').length; i++)
                  _numberedStep(
                    i + 1,
                    MarkupText(
                      r.list('solution')[i],
                      style: reelSmallStyle.copyWith(color: Colors.white, fontSize: 16),
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

/// Plain-text unit for labels: `\mathrm{k\Omega}` → "kΩ", `m^2` → "m²", `\mu F` → "µF".
String unitLabel(String unit) {
  const symbols = {
    r'\Omega': 'Ω',
    r'\ohm': 'Ω',
    r'\mu': 'µ',
    r'\micro': 'µ',
    r'\circ': '°',
    r'\degree': '°',
    r'\cdot': '·',
    r'\pi': 'π',
    r'\%': '%',
  };
  const superscripts = {
    '-': '⁻',
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
  };
  var u = unit.replaceAllMapped(RegExp(r'\\(?:mathrm|text|textrm|operatorname)\{([^{}]*)\}'), (m) => m[1]!);
  for (final e in symbols.entries) {
    u = u.replaceAll(RegExp('${RegExp.escape(e.key)}(?![A-Za-z])'), e.value);
  }
  u = u.replaceAllMapped(RegExp(r'\^\{?(-?\d+)\}?'), (m) => m[1]!.split('').map((c) => superscripts[c] ?? c).join());
  u = u.replaceAll('^°', '°');
  return u.replaceAll(RegExp(r'\\[,;:! ]|[{}]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Exposed for tests.
bool calcAnswerCorrect(double given, double expected, double tolerance) =>
    _CalcExerciseReelState.isCorrect(given, expected, tolerance);

/// Exposed for other widgets that only know the type id.
bool isMathReelType(String type) => mathReelTypes.contains(type);
