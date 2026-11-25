import 'dart:math';

import '../../core/models/reel.dart';
import '../../core/util/ids.dart';
import '../reels/reel_types.dart';
import '../ingestion/chunker.dart';
import 'generation_job.dart';

/// Heuristic, key-less reel generator.
///
/// Works fully offline so the app is usable (and testable) without any AI
/// subscription. Quality is basic: it reuses the source's own sentences,
/// picks key terms by frequency and builds gap texts and questions from them.
class OfflineReelGenerator implements ReelGenerator {
  @override
  String get id => 'offline';

  @override
  Future<List<Reel>> generate(GenerationJob job) async {
    if (job.focus != null) return _deepDive(job);
    final analysis = _Analysis(job.chunk.text);
    final random = Random(job.chunk.id.hashCode ^ job.existingSummaries.length ^ (job.focus?.hashCode ?? 0));
    final reels = <Reel>[];
    final usedSentences = <String>{...job.existingSummaries.map((s) => s.replaceAll('…', ''))};
    final perType = <String, int>{};
    final seen = <String>{...job.existingSummaries};
    for (final type in job.reelTypes) {
      // Each repetition of a type within (and across) batches uses a different variant.
      final variant = job.existingSummaries.length + (perType[type] = (perType[type] ?? -1) + 1);
      final data = _build(type, job, analysis, random, usedSentences, variant);
      if (data == null) continue;
      final summary = Reel(
        id: '',
        sourceId: '',
        chunkId: '',
        type: type,
        data: data,
        createdAt: DateTime.now(),
      ).summary;
      if (!seen.add('$type|$summary') || !seen.add(summary)) continue;
      reels.add(
        Reel(
          id: newId('r'),
          sourceId: job.source.id,
          chunkId: job.chunk.id,
          type: type,
          data: data,
          createdAt: DateTime.now(),
          generator: id,
          difficulty: job.difficulty,
          parentReelId: job.parentReelId,
        ),
      );
    }
    if (reels.isEmpty) {
      // Always produce at least an explainer.
      final data = _build('explainer', job, analysis, random, <String>{}, 0);
      if (data != null) {
        reels.add(
          Reel(
            id: newId('r'),
            sourceId: job.source.id,
            chunkId: job.chunk.id,
            type: 'explainer',
            data: data,
            createdAt: DateTime.now(),
            generator: id,
            difficulty: job.difficulty,
          ),
        );
      }
    }
    return reels;
  }

  Map<String, dynamic>? _build(String type, GenerationJob job, _Analysis a, Random rnd, Set<String> used, int variant) {
    final maxWords = job.settings.maxWordsPerReel;
    final de = a.isGerman;
    String pickSentence({bool withKeyword = false}) {
      final candidates = a.sentences
          .where((s) => !used.any((u) => u.isNotEmpty && s.startsWith(u.substring(0, min(30, u.length)))))
          .toList();
      final pool = (withKeyword ? candidates.where((s) => a.keywordIn(s) != null).toList() : candidates);
      final list = pool.isNotEmpty ? pool : (candidates.isNotEmpty ? candidates : a.sentences);
      if (list.isEmpty) return '';
      // Prefer informative sentences (higher score) with some randomness.
      list.sort((x, y) => a.score(y).compareTo(a.score(x)));
      final s = list[rnd.nextInt(min(3, list.length))];
      used.add(s);
      return s;
    }

    final title = job.chunk.title.replaceAll(RegExp(r'^#+\s*'), '');
    switch (type) {
      case 'explainer':
        // Rotate through the section so repeated generations differ.
        final start = a.sentences.length <= 3 ? 0 : (variant * 3) % (a.sentences.length - 2);
        final body = _limitWords(a.sentences.skip(start).take(3).join(' '), maxWords);
        if (body.isEmpty) return null;
        final takeaway = a.sentences.length > 1 ? _limitWords(a.bestSentence ?? '', 25) : '';
        return {
          'title': title,
          'body': body,
          'takeaway': takeaway == body ? '' : takeaway,
          'emoji': job.settings.useEmojis ? '💡' : '',
        };
      case 'key_points':
        final top = List.of(a.sentences)..sort((x, y) => a.score(y).compareTo(a.score(x)));
        final skip = top.length <= 4 ? 0 : (variant * 2) % (top.length - 3);
        final chosen = top.skip(skip).take(4).toList()
          ..sort((x, y) => a.sentences.indexOf(x).compareTo(a.sentences.indexOf(y)));
        if (chosen.length < 2) return null;
        return {
          'title': de ? 'Das Wichtigste: $title' : 'Key points: $title',
          'points': chosen.map((s) => _limitWords(s, 22)).toList(),
          'emoji': job.settings.useEmojis ? '📌' : '',
        };
      case 'cloze':
      case 'flashcard':
      case 'quiz':
      case 'true_false':
        final sentence = pickSentence(withKeyword: true);
        final keyword = a.keywordIn(sentence);
        if (sentence.isEmpty || keyword == null) return null;
        final gapped = sentence.replaceFirst(RegExp('\\b${RegExp.escape(keyword)}\\b'), '____');
        if (type == 'cloze') {
          return {
            'text': _limitWords(gapped, maxWords),
            'answer': keyword,
            'hint': '${keyword.length} ${de ? 'Buchstaben' : 'letters'}',
          };
        }
        if (type == 'flashcard') {
          final def = a.definition(sentence);
          if (def != null) {
            return {
              'front': de ? 'Was ist/sind „${def.$1}“?' : 'What is "${def.$1}"?',
              'back': _limitWords(def.$2, maxWords),
              'hint': '',
            };
          }
          return {'front': _limitWords(gapped, maxWords), 'back': keyword, 'hint': ''};
        }
        final distractors = a.distractorsFor(keyword, rnd);
        if (type == 'quiz') {
          if (distractors.length < 2) return null;
          final options = [keyword, ...distractors.take(3)]..shuffle(rnd);
          return {
            'question': '${de ? 'Ergänze die Lücke' : 'Fill in the blank'}: ${_limitWords(gapped, maxWords)}',
            'options': options,
            'answer_index': options.indexOf(keyword),
            'explanation': _limitWords(sentence, maxWords),
          };
        }
        final makeFalse = distractors.isNotEmpty && rnd.nextBool();
        final statement = makeFalse
            ? sentence.replaceFirst(RegExp('\\b${RegExp.escape(keyword)}\\b'), distractors.first)
            : sentence;
        return {
          'statement': _limitWords(statement, maxWords),
          'answer': !makeFalse,
          'explanation': makeFalse
              ? (de
                    ? 'Richtig wäre: ${_limitWords(sentence, maxWords)}'
                    : 'Correct: ${_limitWords(sentence, maxWords)}')
              : '',
        };
      case 'write_recall':
        final points = (List.of(a.sentences)..sort((x, y) => a.score(y).compareTo(a.score(x)))).take(3).toList();
        if (points.isEmpty) return null;
        return {
          'prompt': de
              ? 'Schreib oder skizziere aus dem Gedächtnis: Was weißt du über „$title“?'
              : 'From memory, write or sketch: what do you know about "$title"?',
          'model_answer': points.map((s) => '• ${_limitWords(s, 25)}').join('\n'),
          'key_terms': a.keywords.take(5).toList(),
        };
      case 'mnemonic':
        final offset = a.keywords.length <= 4 ? 0 : (variant * 3) % (a.keywords.length - 3);
        final terms = a.keywords.skip(offset).take(4).toList();
        if (terms.length < 2) return null;
        final acronym = terms.map((t) => t[0].toUpperCase()).join();
        return {
          'concept': title,
          'hook': '$acronym — ${terms.join(', ')}',
          'explanation': de
              ? 'Merke dir die Anfangsbuchstaben der Schlüsselbegriffe dieses Abschnitts.'
              : 'Remember the first letters of this section\'s key terms.',
        };
    }
    return null;
  }

  /// "Explain more" without AI: surface the sentences around the focused content.
  List<Reel> _deepDive(GenerationJob job) {
    final a = _Analysis(job.chunk.text);
    if (a.sentences.isEmpty) return const [];
    final focusWords = RegExp(r"[A-Za-zÀ-ž]{4,}").allMatches(job.focus!.toLowerCase()).map((m) => m[0]!).toSet();
    int overlap(String s) =>
        RegExp(r"[A-Za-zÀ-ž]{4,}").allMatches(s.toLowerCase()).where((m) => focusWords.contains(m[0])).length;
    var best = 0;
    for (var i = 1; i < a.sentences.length; i++) {
      if (overlap(a.sentences[i]) > overlap(a.sentences[best])) best = i;
    }
    final from = max(0, best - 1);
    final context = a.sentences.sublist(from, min(a.sentences.length, best + 3));
    final de = a.isGerman;
    final maxWords = job.settings.maxWordsPerReel;
    final title = job.chunk.title.replaceAll(RegExp(r'^#+\s*'), '');
    Reel make(String type, Map<String, dynamic> data) => Reel(
      id: newId('r'),
      sourceId: job.source.id,
      chunkId: job.chunk.id,
      type: type,
      data: data,
      createdAt: DateTime.now(),
      generator: id,
      difficulty: job.difficulty,
      parentReelId: job.parentReelId,
    );
    final reels = <Reel>[
      make('explainer', {
        'title': de ? 'Genauer hingeschaut: $title' : 'Deep dive: $title',
        'body': _limitWords(context.join(' '), maxWords + 30),
        'takeaway': _limitWords(a.sentences[best], 30),
        'emoji': job.settings.useEmojis ? '🔎' : '',
      }),
    ];
    final terms = a.keywords.where((k) => context.any((s) => s.contains(k))).take(5).toList();
    if (terms.length >= 2) {
      reels.add(
        make('key_points', {
          'title': de ? 'Schlüsselbegriffe' : 'Key terms in context',
          'points': <String>{
            for (final t in terms)
              _limitWords(context.firstWhere((s) => s.contains(t), orElse: () => t).replaceFirst(t, '**$t**'), 22),
          }.toList(),
          'emoji': job.settings.useEmojis ? '🧩' : '',
        }),
      );
    }
    final keyword = a.keywordIn(a.sentences[best]);
    if (keyword != null) {
      reels.add(
        make('cloze', {
          'text': _limitWords(
            a.sentences[best].replaceFirst(RegExp('\\b${RegExp.escape(keyword)}\\b'), '____'),
            maxWords,
          ),
          'answer': keyword,
          'hint': '',
        }),
      );
    }
    return reels.where((r) => ReelTypes.byId(r.type)?.normalize(Map.of(r.data)) != null).toList();
  }

  static String _limitWords(String text, int maxWords) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return text.trim();
    return '${words.take(maxWords).join(' ')}…';
  }
}

class _Analysis {
  _Analysis(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'^#+\s.*$', multiLine: true), ' ')
        .replaceAll(RegExp(r'^\s*[-•]\s*', multiLine: true), '');
    sentences = splitSentences(cleaned).where((s) {
      final n = s.split(' ').length;
      return n >= 5 && n <= 45;
    }).toList();
    final words = RegExp(r"[A-Za-zÀ-ž][A-Za-zÀ-ž\-']{2,}").allMatches(cleaned).map((m) => m[0]!).toList();
    isGerman =
        words.where((w) => _deStop.contains(w.toLowerCase())).length >
        words.where((w) => _enStop.contains(w.toLowerCase())).length;
    final freq = <String, int>{};
    final display = <String, String>{};
    for (final w in words) {
      final lower = w.toLowerCase();
      if (_enStop.contains(lower) || _deStop.contains(lower) || lower.length < 4) continue;
      freq[lower] = (freq[lower] ?? 0) + 1;
      display.putIfAbsent(lower, () => w);
    }
    double termScore(String lower) {
      final f = freq[lower]!;
      final w = display[lower]!;
      final capitalBonus = !isGerman && w[0] == w[0].toUpperCase() ? 1.3 : 1.0;
      return f * (1 + min(lower.length, 14) / 7) * capitalBonus;
    }

    final ranked = freq.keys.toList()..sort((a, b) => termScore(b).compareTo(termScore(a)));
    final picked = <String>[];
    for (final k in ranked) {
      final stem = k.substring(0, min(5, k.length));
      if (picked.any((p) => p.startsWith(stem) || k.startsWith(p.substring(0, min(5, p.length))))) continue;
      picked.add(k);
      if (picked.length >= 14) break;
    }
    keywords = picked.map((k) => display[k]!).toList();
    _termScores = {for (final k in ranked) k: termScore(k)};
    bestSentence = sentences.isEmpty ? null : (List.of(sentences)..sort((x, y) => score(y).compareTo(score(x)))).first;
  }

  late final List<String> sentences;
  late final List<String> keywords;
  late final bool isGerman;
  late final Map<String, double> _termScores;
  String? bestSentence;

  double score(String sentence) {
    var s = 0.0;
    for (final m in RegExp(r"[A-Za-zÀ-ž][A-Za-zÀ-ž\-']{2,}").allMatches(sentence)) {
      s += _termScores[m[0]!.toLowerCase()] ?? 0;
    }
    return s / (1 + sentence.split(' ').length / 12);
  }

  /// The highest-ranked keyword occurring in [sentence] (not at its very start).
  String? keywordIn(String sentence) {
    for (final k in keywords) {
      final idx = sentence.indexOf(RegExp('\\b${RegExp.escape(k)}\\b'));
      if (idx > 0) return k;
    }
    for (final k in keywords) {
      if (sentence.contains(RegExp('\\b${RegExp.escape(k)}\\b'))) return k;
    }
    return null;
  }

  List<String> distractorsFor(String keyword, Random rnd) {
    final pool = keywords.where((k) => k.toLowerCase() != keyword.toLowerCase()).toList();
    pool.sort((a, b) => (a.length - keyword.length).abs().compareTo((b.length - keyword.length).abs()));
    final top = pool.take(6).toList()..shuffle(rnd);
    return top.take(3).toList();
  }

  static final _definitionRe = RegExp(
    r'^(?:The |A |An |Der |Die |Das |Ein |Eine )?([A-ZÄÖÜa-zäöüß][\wÄÖÜäöüß\- ]{1,40}?)\s+(is|are|refers to|means|describes|ist|sind|bezeichnet|beschreibt|bedeutet)\s+(.{8,})$',
  );

  (String, String)? definition(String sentence) {
    final m = _definitionRe.firstMatch(sentence);
    if (m == null) return null;
    final term = m[1]!.trim();
    final words = term.split(' ');
    if (words.length > 3) return null;
    // Sentence starters like "Each time", "This", "There" are not terms.
    if (_notTerms.contains(words.first.toLowerCase()) ||
        _enStop.contains(words.first.toLowerCase()) ||
        _deStop.contains(words.first.toLowerCase())) {
      return null;
    }
    return (term, '${term[0].toUpperCase()}${term.substring(1)} ${m[2]} ${m[3]}');
  }
}

const _notTerms = {
  'each',
  'every',
  'this',
  'that',
  'these',
  'those',
  'it',
  'they',
  'there',
  'here',
  'what',
  'which',
  'who',
  'when',
  'while',
  'where',
  'why',
  'how',
  'some',
  'many',
  'most',
  'all',
  'such',
  'one',
  'another',
  'other',
  'jede',
  'jeder',
  'jedes',
  'dies',
  'diese',
  'dieser',
  'dieses',
  'es',
  'man',
  'hier',
  'dort',
  'wenn',
  'wo',
  'wie',
  'was',
  'viele',
};

const _enStop = {
  'the',
  'and',
  'for',
  'are',
  'but',
  'not',
  'you',
  'all',
  'any',
  'can',
  'had',
  'her',
  'was',
  'one',
  'our',
  'out',
  'has',
  'have',
  'his',
  'how',
  'its',
  'may',
  'new',
  'now',
  'see',
  'two',
  'way',
  'who',
  'did',
  'get',
  'him',
  'let',
  'use',
  'that',
  'with',
  'this',
  'from',
  'they',
  'will',
  'would',
  'there',
  'their',
  'what',
  'about',
  'which',
  'when',
  'make',
  'like',
  'time',
  'just',
  'know',
  'take',
  'into',
  'year',
  'your',
  'some',
  'could',
  'them',
  'than',
  'then',
  'only',
  'come',
  'over',
  'also',
  'back',
  'after',
  'used',
  'first',
  'well',
  'even',
  'want',
  'because',
  'these',
  'give',
  'most',
  'very',
  'such',
  'each',
  'other',
  'more',
  'many',
  'much',
  'been',
  'were',
  'being',
  'does',
  'where',
  'while',
  'through',
  'between',
  'both',
  'those',
  'often',
  'called',
  'within',
  'without',
  'however',
  'therefore',
  'example',
  'is',
  'of',
  'to',
  'in',
  'it',
  'as',
  'on',
  'be',
  'by',
  'or',
  'an',
  'at',
  'if',
  'so',
  'we',
  'should',
  'must',
  'might',
  'every',
  'same',
  'different',
  'need',
  'needs',
  'happens',
  'directly',
  'specific',
};

const _deStop = {
  'der',
  'die',
  'das',
  'und',
  'oder',
  'aber',
  'nicht',
  'ein',
  'eine',
  'einer',
  'eines',
  'einem',
  'einen',
  'ist',
  'sind',
  'war',
  'waren',
  'wird',
  'werden',
  'wurde',
  'wurden',
  'hat',
  'haben',
  'hatte',
  'mit',
  'von',
  'für',
  'auf',
  'aus',
  'bei',
  'nach',
  'vor',
  'über',
  'unter',
  'durch',
  'gegen',
  'ohne',
  'um',
  'zum',
  'zur',
  'dem',
  'den',
  'des',
  'im',
  'in',
  'an',
  'am',
  'als',
  'auch',
  'noch',
  'nur',
  'schon',
  'sehr',
  'wie',
  'wenn',
  'dass',
  'weil',
  'sich',
  'sie',
  'er',
  'es',
  'wir',
  'ihr',
  'man',
  'kann',
  'können',
  'muss',
  'müssen',
  'soll',
  'sollen',
  'diese',
  'dieser',
  'dieses',
  'diesem',
  'diesen',
  'jede',
  'jeder',
  'jedes',
  'alle',
  'allem',
  'allen',
  'mehr',
  'viele',
  'vielen',
  'wobei',
  'sowie',
  'bzw',
  'zwischen',
  'während',
  'zwei',
  'drei',
  'kein',
  'keine',
  'keinen',
  'besitzen',
  'unterscheidet',
  'umgebenen',
  'ihre',
  'ihren',
  'seine',
  'seinen',
  'dabei',
  'daher',
  'somit',
  'also',
};
