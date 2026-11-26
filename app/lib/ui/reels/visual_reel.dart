import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import '../../modules/visuals/expression.dart';
import '../../modules/visuals/visual_spec.dart';
import '../visuals/chart.dart';
import '../visuals/controls.dart';
import '../visuals/math_text.dart';
import '../visuals/plot.dart';
import '../visuals/svg_view.dart';
import '../widgets/rich_text.dart';
import 'reel_common.dart';

/// Interactive / animated visual: function plot, chart, SVG sketch,
/// step-by-step equation or a figure from the source, plus controls.
class VisualReel extends StatefulWidget {
  const VisualReel(this.ctx, {super.key});
  final ReelContext ctx;

  @override
  State<VisualReel> createState() => _VisualReelState();
}

class _VisualReelState extends State<VisualReel> with SingleTickerProviderStateMixin {
  late final VisualSpec spec = VisualSpec(widget.ctx.reel.data);
  late final Map<String, double> _params;
  AnimationController? _anim;

  bool get _challengeDone => widget.ctx.recall<bool>('challengeDone') ?? false;
  int get _stepsShown => widget.ctx.recall<int>('steps') ?? 0;

  @override
  void initState() {
    super.initState();
    final saved = widget.ctx.recall<Map<String, double>>('params');
    _params = saved ?? spec.initialParams();
    widget.ctx.remember('params', _params);
    final a = spec.animation;
    if (a != null) {
      _anim =
          AnimationController(
            vsync: this,
            duration: Duration(milliseconds: (a.seconds * 1000).round()),
          )..addListener(() {
            setState(() => _params[a.param] = lerpDouble(a.from, a.to, _anim!.value)!);
            _checkChallenge();
          });
      if (a.autoplay) _play();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkChallenge());
  }

  void _play() {
    final a = spec.animation!;
    if (a.loop) {
      _anim!.repeat();
    } else {
      _anim!.forward(from: _anim!.isCompleted ? 0 : null);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _anim?.dispose();
    super.dispose();
  }

  void _set(String param, double value) {
    setState(() => _params[param] = value);
    _checkChallenge();
  }

  void _reset() {
    final initial = spec.initialParams();
    setState(() {
      for (final c in spec.controls) {
        _params[c.param] = initial[c.param] ?? c.initial;
      }
    });
  }

  void _checkChallenge() {
    final c = spec.challenge;
    if (c == null || _challengeDone || !mounted) return;
    if (Expression.eval(c.condition, _params) != 0 && Expression.eval(c.condition, _params).isFinite) {
      setState(() => widget.ctx.remember('challengeDone', true));
      widget.ctx.onAnswer(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = spec.controls;
    final dials = controls.where((c) => c.kind == 'dial').toList();
    final others = controls.where((c) => c.kind != 'dial').toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.title.isNotEmpty) MarkupText(spec.title, style: reelTitleStyle.copyWith(fontSize: 23)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.3), child: _visual()),
        ),
        if (_anim != null) _animationBar(),
        if (spec.caption.isNotEmpty) ...[
          const SizedBox(height: 12),
          MarkupText(spec.caption, style: reelBodyStyle.copyWith(fontSize: 17)),
        ],
        if (controls.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dials.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final c in dials)
                        ParamControl(spec: c, value: _params[c.param] ?? c.initial, onChanged: (v) => _set(c.param, v)),
                    ],
                  ),
                for (final c in others)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ParamControl(
                      spec: c,
                      value: _params[c.param] ?? c.initial,
                      onChanged: (v) => _set(c.param, v),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt, size: 18, color: Colors.white70),
                    label: const Text('Reset', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (spec.challenge != null) ...[const SizedBox(height: 10), _challenge(spec.challenge!)],
      ],
    );
  }

  Widget _visual() {
    switch (spec.kind) {
      case 'function_plot':
        return AspectRatio(
          aspectRatio: 4 / 3,
          child: FunctionPlot(spec: spec, params: _params),
        );
      case 'chart':
        return AspectRatio(
          aspectRatio: 4 / 3,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ChartView(spec: spec, params: _params),
          ),
        );
      case 'diagram':
        return AspectRatio(
          aspectRatio: 16 / 11,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LiveSvg(VisualNormalizer.renderSvgTemplate(spec.svg, _params)),
          ),
        );
      case 'equation':
        return _equation();
      case 'image':
        return _image();
    }
    return const SizedBox(
      height: 120,
      child: Center(child: Text('Unsupported visual', style: reelSmallStyle)),
    );
  }

  Widget _equation() {
    final steps = spec.steps;
    final shown = _stepsShown.clamp(0, steps.length);
    const mathStyle = TextStyle(color: Colors.white, fontSize: 26);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: MathTex(spec.latex, style: mathStyle, display: true)),
          for (var i = 0; i < shown; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey('step$i'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 350),
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.white24,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (steps[i].latex.isNotEmpty)
                            MathTex(steps[i].latex, style: mathStyle.copyWith(fontSize: 20), display: true),
                          if (steps[i].note.isNotEmpty) MarkupText(steps[i].note, style: reelSmallStyle),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (shown < steps.length)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => widget.ctx.remember('steps', steps.length)),
                    child: const Text('Show all', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => setState(() => widget.ctx.remember('steps', shown + 1)),
                    icon: const Icon(Icons.navigate_next),
                    label: Text('Step ${shown + 1} of ${steps.length}'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _image() {
    final ctx = widget.ctx;
    Widget child;
    final file = spec.imageId.isEmpty ? null : ctx.imageFile?.call(ctx.reel.sourceId, spec.imageId);
    Widget placeholder(String note) => SizedBox(
      height: 160,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '🖼  ${spec.alt.isEmpty ? 'Figure' : spec.alt}\n$note',
            textAlign: TextAlign.center,
            style: reelSmallStyle,
          ),
        ),
      ),
    );
    if (file != null && file.existsSync()) {
      child = Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => placeholder('The image could not be loaded.'),
      );
    } else if (spec.imageUrl.isNotEmpty && ctx.allowWebImages) {
      child = Image.network(
        spec.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => placeholder('The image could not be loaded.'),
      );
    } else if (spec.imageUrl.isNotEmpty) {
      child = placeholder('Web images are turned off (Settings → Reel generation).');
    } else {
      child = placeholder('The figure is not available.');
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360, minHeight: 120),
      child: Container(color: Colors.white.withValues(alpha: 0.92), alignment: Alignment.center, child: child),
    );
  }

  Widget _animationBar() {
    final anim = _anim!;
    return Row(
      children: [
        IconButton(
          tooltip: anim.isAnimating ? 'Pause' : 'Play',
          icon: Icon(anim.isAnimating ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 30),
          onPressed: () => anim.isAnimating ? setState(anim.stop) : _play(),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3),
            child: Slider(
              value: anim.value,
              onChanged: (v) {
                anim.stop();
                anim.value = v;
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _challenge(ChallengeSpec c) {
    final done = _challengeDone;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done ? const Color(0xCC2E7D32) : Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? const Color(0xFFA5D6A7) : Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(done ? '✅' : '🎯', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: MarkupText(
              done ? (c.success.isEmpty ? 'Goal reached! ${c.prompt}' : c.success) : c.prompt,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
