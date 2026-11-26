import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/models/reel.dart';
import '../../core/models/settings.dart';
import '../../core/storage/repositories.dart';
import '../../modules/study/progress_tracker.dart';

/// Callbacks and context handed to every reel body widget.
class ReelContext {
  ReelContext({
    required this.reel,
    required this.onAnswer,
    required this.onRate,
    required this.pen,
    required this.annotations,
    required this.memory,
    this.imageFile,
    this.allowWebImages = false,
  });

  final Reel reel;

  /// Objective answer (quiz, true/false, cloze).
  final void Function(bool correct) onAnswer;

  /// Self-assessment (flashcards, write-from-memory).
  final void Function(RecallRating rating) onRate;
  final PenSettings pen;
  final AnnotationRepository annotations;

  /// Session memory so interactions survive scrolling away and back.
  final Map<String, Object?> memory;

  /// Resolves a figure extracted from a source (`img3`) to its file.
  final File? Function(String sourceId, String imageId)? imageFile;

  /// Whether visuals may load images from the internet.
  final bool allowWebImages;

  T? recall<T>(String key) => memory['${reel.id}.$key'] as T?;
  void remember(String key, Object? value) => memory['${reel.id}.$key'] = value;
}

const reelTitleStyle = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2);
const reelBodyStyle = TextStyle(fontSize: 20, color: Colors.white, height: 1.45);
const reelSmallStyle = TextStyle(fontSize: 15, color: Colors.white70, height: 1.4);

/// Translucent rounded panel used inside reels.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: child,
  );
}

/// Again / Hard / Good / Easy buttons for self-rated recall.
class RatingBar extends StatelessWidget {
  const RatingBar({super.key, required this.onRate, this.selected});
  final void Function(RecallRating) onRate;
  final RecallRating? selected;

  static const labels = {
    RecallRating.again: ('Again', Color(0xFFFF6E6E)),
    RecallRating.hard: ('Hard', Color(0xFFFFB74D)),
    RecallRating.good: ('Good', Color(0xFF81C784)),
    RecallRating.easy: ('Easy', Color(0xFF4FC3F7)),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('How well did you know it?', style: reelSmallStyle),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in labels.entries)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: selected == null || selected == entry.key
                      ? entry.value.$2.withValues(alpha: 0.9)
                      : entry.value.$2.withValues(alpha: 0.25),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(76, 44),
                ),
                onPressed: selected == null ? () => onRate(entry.key) : null,
                child: Text(entry.value.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Feedback banner after answering.
class AnswerFeedback extends StatelessWidget {
  const AnswerFeedback({super.key, required this.correct, this.explanation = '', this.correctAnswer});
  final bool correct;
  final String explanation;
  final String? correctAnswer;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: GlassPanel(
        color: (correct ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C)).withValues(alpha: 0.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(correct ? Icons.check_circle : Icons.cancel, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  correct ? 'Correct!' : 'Not quite',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ],
            ),
            if (!correct && correctAnswer != null) ...[
              const SizedBox(height: 6),
              Text(
                'Answer: $correctAnswer',
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(explanation, style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loose answer comparison for typed answers (case, accents, punctuation, small typos).
bool answersMatch(String given, String expected) {
  String norm(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9à-ž ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^(the|a|an|der|die|das|ein|eine) '), '')
      .trim();
  final a = norm(given), b = norm(expected);
  if (a.isEmpty) return false;
  if (a == b) return true;
  final tolerance = b.length > 10 ? 2 : (b.length > 4 ? 1 : 0);
  return _levenshtein(a, b) <= tolerance;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}
