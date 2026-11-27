import '../../core/util/json.dart';
import '../visuals/expression.dart';
import '../visuals/visual_spec.dart';

/// Describes one kind of reel: how the AI should produce it and how raw
/// model output is validated. The matching widget lives in
/// `ui/reels/reel_widgets.dart`.
///
/// To add a new reel type: implement [ReelTypeSpec], register it in
/// [ReelTypes.all] and add a widget builder for its [id].
abstract class ReelTypeSpec {
  const ReelTypeSpec();

  String get id;
  String get label;
  String get description;

  /// Whether the reel tests recall and should be scheduled for spaced repetition.
  bool get isRecall;

  /// Whether the reel teaches (shown before questions in linear modes).
  bool get isTeaching => !isRecall;

  /// One-line JSON example used in the prompt.
  String get promptFormat;

  /// Extra writing guidance for the model.
  String get promptGuidance;

  /// JSON schema of one reel object (all objects must be closed for structured output).
  /// Null for free-form types; requests containing them are sent without a schema.
  Map<String, Object?>? get jsonSchema;

  /// Validates and cleans a raw model object; returns null if unusable.
  Map<String, dynamic>? normalize(Map<String, dynamic> raw);
}

Map<String, Object?> _objectSchema(String type, Map<String, Object?> props) => {
  'type': 'object',
  'properties': {
    'type': {
      'type': 'string',
      'enum': [type],
    },
    ...props,
  },
  'required': ['type', ...props.keys],
  'additionalProperties': false,
};

const _str = {'type': 'string'};
const _strList = {
  'type': 'array',
  'items': {'type': 'string'},
};

String _clean(Object? v) => jString(v).replaceAll(RegExp(r'\s+\n'), '\n').trim();
List<String> _cleanList(Object? v) => jStringList(v).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

class ExplainerSpec extends ReelTypeSpec {
  const ExplainerSpec();
  @override
  String get id => 'explainer';
  @override
  String get label => 'Explainer';
  @override
  String get description => 'A short, vivid explanation of one idea.';
  @override
  bool get isRecall => false;
  @override
  String get promptFormat =>
      '{"type":"explainer","title":"…","body":"2-4 short sentences","takeaway":"one-sentence key insight","emoji":"🧬"}';
  @override
  String get promptGuidance =>
      'Explain ONE idea with a hook in the first sentence; concrete examples beat abstractions.';
  @override
  Map<String, Object?> get jsonSchema =>
      _objectSchema(id, {'title': _str, 'body': _str, 'takeaway': _str, 'emoji': _str});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final body = _clean(raw['body'] ?? raw['text'] ?? raw['explanation']);
    if (body.length < 10) return null;
    return {
      'title': _clean(raw['title']),
      'body': body,
      'takeaway': _clean(raw['takeaway'] ?? raw['key_takeaway']),
      'emoji': _clean(raw['emoji']),
    };
  }
}

class KeyPointsSpec extends ReelTypeSpec {
  const KeyPointsSpec();
  @override
  String get id => 'key_points';
  @override
  String get label => 'Key points';
  @override
  String get description => '3–5 bullet points that summarise a section.';
  @override
  bool get isRecall => false;
  @override
  String get promptFormat => '{"type":"key_points","title":"…","points":["…","…","…"],"emoji":"📌"}';
  @override
  String get promptGuidance => '3-5 points, each one line, most important first.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {'title': _str, 'points': _strList, 'emoji': _str});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final points = _cleanList(raw['points'] ?? raw['bullets']);
    if (points.length < 2) return null;
    return {'title': _clean(raw['title']), 'points': points.take(6).toList(), 'emoji': _clean(raw['emoji'])};
  }
}

class QuizSpec extends ReelTypeSpec {
  const QuizSpec();
  @override
  String get id => 'quiz';
  @override
  String get label => 'Multiple choice';
  @override
  String get description => 'A question with four options.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"quiz","question":"…","options":["A","B","C","D"],"answer_index":0,"explanation":"why the answer is right"}';
  @override
  String get promptGuidance =>
      'Exactly 4 options, one correct; plausible distractors of similar length; vary the position of the correct answer.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {
    'question': _str,
    'options': _strList,
    'answer_index': {'type': 'integer'},
    'explanation': _str,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final question = _clean(raw['question']);
    final options = _cleanList(raw['options'] ?? raw['choices']);
    var answer = jInt(raw['answer_index'] ?? raw['answerIndex'] ?? raw['correct_index'], -1);
    if (answer < 0 && raw['answer'] is String) answer = options.indexOf(_clean(raw['answer']));
    if (question.isEmpty || options.length < 2 || answer < 0 || answer >= options.length) return null;
    return {
      'question': question,
      'options': options.take(6).toList(),
      'answer_index': answer,
      'explanation': _clean(raw['explanation']),
    };
  }
}

class TrueFalseSpec extends ReelTypeSpec {
  const TrueFalseSpec();
  @override
  String get id => 'true_false';
  @override
  String get label => 'True or false';
  @override
  String get description => 'Decide whether a statement is correct.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat => '{"type":"true_false","statement":"…","answer":true,"explanation":"…"}';
  @override
  String get promptGuidance => 'False statements must be subtly wrong (a swapped term or number), never absurd.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {
    'statement': _str,
    'answer': {'type': 'boolean'},
    'explanation': _str,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final statement = _clean(raw['statement'] ?? raw['question']);
    final answer = raw['answer'] ?? raw['is_true'];
    if (statement.isEmpty || (answer is! bool && answer is! String)) return null;
    return {
      'statement': statement,
      'answer': answer is bool ? answer : answer.toString().toLowerCase().startsWith('t'),
      'explanation': _clean(raw['explanation']),
    };
  }
}

class FlashcardSpec extends ReelTypeSpec {
  const FlashcardSpec();
  @override
  String get id => 'flashcard';
  @override
  String get label => 'Flashcard';
  @override
  String get description => 'Front/back card for memorising facts and definitions.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"flashcard","front":"term or question","back":"precise answer","hint":"optional nudge"}';
  @override
  String get promptGuidance =>
      'One fact per card. Use the exact wording of definitions from the source when it matters.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {'front': _str, 'back': _str, 'hint': _str});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final front = _clean(raw['front'] ?? raw['question'] ?? raw['term']);
    final back = _clean(raw['back'] ?? raw['answer'] ?? raw['definition']);
    if (front.isEmpty || back.isEmpty) return null;
    return {'front': front, 'back': back, 'hint': _clean(raw['hint'])};
  }
}

class ClozeSpec extends ReelTypeSpec {
  const ClozeSpec();
  @override
  String get id => 'cloze';
  @override
  String get label => 'Fill the gap';
  @override
  String get description => 'A sentence with a missing key term.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"cloze","text":"The ____ produces ATP.","answer":"mitochondrion","hint":"organelle"}';
  @override
  String get promptGuidance => 'Exactly one gap written as ____ ; the answer is 1-3 words.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {'text': _str, 'answer': _str, 'hint': _str});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    var text = _clean(raw['text'] ?? raw['sentence']);
    final answer = _clean(raw['answer']);
    if (text.isEmpty || answer.isEmpty) return null;
    text = text.replaceAll(RegExp(r'\{\{[^}]*\}\}|\[blank\]|_{2,}|\.{4,}|…{2,}'), '____');
    if (!text.contains('____')) {
      final idx = text.toLowerCase().indexOf(answer.toLowerCase());
      if (idx < 0) return null;
      text = '${text.substring(0, idx)}____${text.substring(idx + answer.length)}';
    }
    return {'text': text, 'answer': answer, 'hint': _clean(raw['hint'])};
  }
}

class WriteRecallSpec extends ReelTypeSpec {
  const WriteRecallSpec();
  @override
  String get id => 'write_recall';
  @override
  String get label => 'Write from memory';
  @override
  String get description => 'Handwrite (pen) or type an answer from memory, then compare.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"write_recall","prompt":"Explain/sketch/list … from memory","model_answer":"…","key_terms":["…","…"]}';
  @override
  String get promptGuidance =>
      'An open recall task that can be answered by writing or sketching in under a minute (definitions, steps, a formula, a diagram).';
  @override
  Map<String, Object?> get jsonSchema =>
      _objectSchema(id, {'prompt': _str, 'model_answer': _str, 'key_terms': _strList});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final prompt = _clean(raw['prompt'] ?? raw['question']);
    final answer = _clean(raw['model_answer'] ?? raw['answer']);
    if (prompt.isEmpty || answer.isEmpty) return null;
    return {'prompt': prompt, 'model_answer': answer, 'key_terms': _cleanList(raw['key_terms']).take(8).toList()};
  }
}

class MnemonicSpec extends ReelTypeSpec {
  const MnemonicSpec();
  @override
  String get id => 'mnemonic';
  @override
  String get label => 'Memory hook';
  @override
  String get description => 'A mnemonic, analogy or story that makes a fact stick.';
  @override
  bool get isRecall => false;
  @override
  String get promptFormat =>
      '{"type":"mnemonic","concept":"what to remember","hook":"the mnemonic/analogy","explanation":"how it maps"}';
  @override
  String get promptGuidance => 'Acronyms, rhymes, vivid images or analogies. Must map accurately to the facts.';
  @override
  Map<String, Object?> get jsonSchema => _objectSchema(id, {'concept': _str, 'hook': _str, 'explanation': _str});
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final concept = _clean(raw['concept'] ?? raw['title']);
    final hook = _clean(raw['hook'] ?? raw['mnemonic']);
    if (concept.isEmpty || hook.isEmpty) return null;
    return {'concept': concept, 'hook': hook, 'explanation': _clean(raw['explanation'])};
  }
}

/// Interactive / animated graphics: function plots, charts, SVG sketches,
/// step-by-step equations and figures from the source, with sliders, dials,
/// buttons and optional goals ("challenges").
class VisualReelSpec extends ReelTypeSpec {
  const VisualReelSpec();
  @override
  String get id => 'visual';
  @override
  String get label => 'Interactive visual';
  @override
  String get description => 'Graphs, charts, sketches, equations and figures you can manipulate.';
  @override
  bool get isRecall => false;
  @override
  String get promptFormat =>
      '{"type":"visual","title":"…","caption":"1-2 sentences, may use \$LaTeX\$","visual":{…one of the kinds below…},'
      '"controls":[…0-3 controls…],"animate":null,"challenge":null}\n'
      '  visual kinds:\n'
      '  • {"kind":"function_plot","x_min":-5,"x_max":5,"y_min":null,"y_max":null,"x_label":"x","y_label":"y",'
      '"functions":[{"expr":"a*x^2+b","label":"f(x)","color":"#FFD54F"}],"points":[{"x":"0","y":"b","label":"vertex"}]}\n'
      '  • {"kind":"chart","chart_type":"bar|line|pie","labels":["2019","2020"],"series":[{"name":"…","values":["3.1","2.4*g"]}]}\n'
      '  • {"kind":"diagram","svg":"<svg viewBox=\'0 0 320 220\'>…</svg>"}  (a clear sketch/diagram; single quotes for '
      'attributes; {{expression}} placeholders make it interactive or animated, e.g. cx=\'{{160+80*cos(t)}}\')\n'
      '  • {"kind":"equation","latex":"E = mc^2","steps":[{"latex":"…","note":"…"}]}  (derivation revealed step by step)\n'
      '  • {"kind":"image","image_id":"img3","alt":"…"}  (only ids listed under FIGURES)\n'
      '  controls: {"kind":"slider|dial|toggle|buttons|stepper","param":"a","label":"Steepness a","min":-3,"max":3,'
      '"step":0.1,"value":1,"unit":"","options":[{"label":"Linear","value":1}]}  (options only for buttons)\n'
      '  animate: {"param":"t","from":0,"to":6.28,"seconds":4,"loop":true}  drives a time variable for animations\n'
      '  challenge: {"prompt":"Make the parabola open downwards","condition":"a < 0","success":"…"}  a goal reached '
      'by moving the controls\n'
      '  Expressions use + - * / ^, sin cos tan exp ln log sqrt abs min max, pi, e and comparisons (< > == && ||); '
      'x is the plot variable; every other variable must be a control param or the animate param.';
  @override
  String get promptGuidance =>
      'Use visuals where a picture teaches better than words: functions and graphs, quantities and data from the '
      'source, geometry, physics, processes and structures (sketch them as SVG), formulas (equation steps). Make '
      'controls meaningful (parameters of the concept). Never invent data that is not in the source. SVGs are shown on '
      'a dark background: transparent background, light strokes/text (#FFFFFF, #FFD54F, #80DEEA, #FF8A80), '
      'font-size >= 12.';
  @override
  Map<String, Object?>? get jsonSchema => null;
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) => VisualNormalizer.normalize(raw);
}

// ---------------------------------------------------------------------------
// Math & science reel types
// ---------------------------------------------------------------------------

Map<String, Object?> _closed(Map<String, Object?> props) => {
  'type': 'object',
  'properties': props,
  'required': props.keys.toList(),
  'additionalProperties': false,
};

/// Parses numbers written by models or learners: "1.5e16", "1,5·10^16", "6/2".
double? parseNumber(Object? v) {
  if (v is num) return v.toDouble();
  final s = jString(v)
      .trim()
      .replaceAll(RegExp(r'(?<=\d),(?=\d)'), '.')
      .replaceAll(RegExp(r'\s*[·×x*]\s*10\s*\^\s*'), 'e')
      .replaceAll(RegExp(r'\s*[·×]\s*10(?=[⁻⁰¹²³⁴⁵⁶⁷⁸⁹])'), 'e')
      .replaceAllMapped(
        RegExp('[⁻⁰¹²³⁴⁵⁶⁷⁸⁹]'),
        (m) => const {
          '⁻': '-',
          '⁰': '0',
          '¹': '1',
          '²': '2',
          '³': '3',
          '⁴': '4',
          '⁵': '5',
          '⁶': '6',
          '⁷': '7',
          '⁸': '8',
          '⁹': '9',
        }[m[0]]!,
      )
      .replaceAll(RegExp(r'e\(([-+]?\d+)\)'), r'e$1');
  if (s.isEmpty) return null;
  final direct = double.tryParse(s);
  if (direct != null) return direct;
  final value = Expression.eval(s, const {});
  if (value.isFinite) return value;
  // A number followed by a unit: "4.2 V", "3e-5 m", "12 %".
  final lead = RegExp(r'^([-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?)\s*[A-Za-zΩµμ%°]').firstMatch(s);
  return lead == null ? null : double.tryParse(lead[1]!);
}

/// Step-by-step procedure ("Rechenrezept") with a worked example.
class MathRecipeSpec extends ReelTypeSpec {
  const MathRecipeSpec();
  @override
  String get id => 'math_recipe';
  @override
  String get label => 'Recipe (Rechenrezept)';
  @override
  String get description => 'A step-by-step method for a standard calculation, with a worked example.';
  @override
  bool get isRecall => false;
  @override
  String get promptFormat =>
      '{"type":"math_recipe","title":"…","goal":"what the procedure computes","when_to_use":"…",'
      '"steps":[{"action":"imperative instruction","latex":"key formula or empty"}],'
      '"example":{"problem":"…","steps":["…"],"result":"…"},"pitfalls":["…"]}';
  @override
  String get promptGuidance =>
      '3-7 short imperative steps, each with its key formula in LaTeX (may be empty); one fully worked example with '
      'concrete numbers; 1-3 typical mistakes.';
  @override
  Map<String, Object?>? get jsonSchema => _objectSchema(id, {
    'title': _str,
    'goal': _str,
    'when_to_use': _str,
    'steps': {
      'type': 'array',
      'items': _closed({'action': _str, 'latex': _str}),
    },
    'example': _closed({'problem': _str, 'steps': _strList, 'result': _str}),
    'pitfalls': _strList,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final steps = <Map<String, dynamic>>[];
    for (final s in (raw['steps'] is List ? raw['steps'] as List : const [])) {
      final m = s is String ? {'action': s} : jMap(s);
      final action = _clean(m['action'] ?? m['step'] ?? m['text']);
      if (action.isEmpty) continue;
      steps.add({'action': action, 'latex': _clean(m['latex'] ?? m['formula'])});
    }
    if (steps.length < 2) return null;
    final ex = jMap(raw['example']);
    return {
      'title': _clean(raw['title']),
      'goal': _clean(raw['goal']),
      'when_to_use': _clean(raw['when_to_use'] ?? raw['when']),
      'steps': steps.take(10).toList(),
      'example': {
        'problem': _clean(ex['problem']),
        'steps': _cleanList(ex['steps']).take(10).toList(),
        'result': _clean(ex['result']),
      },
      'pitfalls': _cleanList(raw['pitfalls']).take(4).toList(),
    };
  }
}

/// A theorem / law ("Satz", "Gesetz") with assumptions, statement, intuition and proof idea.
class TheoremSpec extends ReelTypeSpec {
  const TheoremSpec();
  @override
  String get id => 'theorem';
  @override
  String get label => 'Theorem (Satz)';
  @override
  String get description => 'A theorem or law with its exact assumptions, statement, intuition and proof idea.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"theorem","kind":"Satz|Theorem|Gesetz|Lemma|Definition","name":"…","assumptions":["…"],'
      '"statement":"…","formula":"LaTeX or empty","intuition":"…","proof_idea":"…","example":"…"}';
  @override
  String get promptGuidance =>
      'State it exactly as in the source with ALL assumptions (Voraussetzungen); key formula in LaTeX; intuition in '
      '1-2 sentences; proof idea in 1-3 sentences; one concrete example.';
  @override
  Map<String, Object?>? get jsonSchema => _objectSchema(id, {
    'kind': _str,
    'name': _str,
    'assumptions': _strList,
    'statement': _str,
    'formula': _str,
    'intuition': _str,
    'proof_idea': _str,
    'example': _str,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final name = _clean(raw['name'] ?? raw['title']);
    final statement = _clean(raw['statement'] ?? raw['aussage']);
    if (name.isEmpty || (statement.isEmpty && _clean(raw['formula']).isEmpty)) return null;
    return {
      'kind': _clean(raw['kind']).isEmpty ? 'Theorem' : _clean(raw['kind']),
      'name': name,
      'assumptions': _cleanList(raw['assumptions'] ?? raw['conditions']).take(6).toList(),
      'statement': statement,
      'formula': _clean(raw['formula'] ?? raw['latex']),
      'intuition': _clean(raw['intuition']),
      'proof_idea': _clean(raw['proof_idea'] ?? raw['proof']),
      'example': _clean(raw['example']),
    };
  }
}

/// A formula with a legend of its symbols and units.
class FormulaCardSpec extends ReelTypeSpec {
  const FormulaCardSpec();
  @override
  String get id => 'formula';
  @override
  String get label => 'Formula card';
  @override
  String get description => 'A key formula with the meaning and unit of every symbol.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"formula","name":"…","latex":"…","symbols":[{"symbol":"LaTeX","meaning":"…","unit":"SI unit or empty"}],'
      '"conditions":"when it holds","intuition":"…"}';
  @override
  String get promptGuidance =>
      'Explain every symbol of the formula; units as in the source (e.g. cm⁻³ in device physics).';
  @override
  Map<String, Object?>? get jsonSchema => _objectSchema(id, {
    'name': _str,
    'latex': _str,
    'symbols': {
      'type': 'array',
      'items': _closed({'symbol': _str, 'meaning': _str, 'unit': _str}),
    },
    'conditions': _str,
    'intuition': _str,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final latex = _clean(raw['latex'] ?? raw['formula']);
    if (latex.isEmpty) return null;
    final symbols = <Map<String, dynamic>>[];
    for (final s in (raw['symbols'] is List ? raw['symbols'] as List : const [])) {
      final m = jMap(s);
      final symbol = _clean(m['symbol']);
      final meaning = _clean(m['meaning'] ?? m['description']);
      if (symbol.isEmpty || meaning.isEmpty) continue;
      symbols.add({'symbol': symbol, 'meaning': meaning, 'unit': _clean(m['unit'])});
    }
    return {
      'name': _clean(raw['name'] ?? raw['title']),
      'latex': latex,
      'symbols': symbols.take(10).toList(),
      'conditions': _clean(raw['conditions']),
      'intuition': _clean(raw['intuition']),
    };
  }
}

/// A numeric calculation exercise; the learner's answer is checked within a tolerance.
class CalcExerciseSpec extends ReelTypeSpec {
  const CalcExerciseSpec();
  @override
  String get id => 'calc_exercise';
  @override
  String get label => 'Calculation';
  @override
  String get description => 'A numeric exercise with given values; your answer is checked.';
  @override
  bool get isRecall => true;
  @override
  String get promptFormat =>
      '{"type":"calc_exercise","problem":"…","given":[{"symbol":"LaTeX","value":"1.5e16","unit":"…"}],'
      '"asked":"what to compute, with symbol","answer":12.3,"unit":"…","tolerance":0.02,"hint":"…",'
      '"solution":["step with formula …","…"]}';
  @override
  String get promptGuidance =>
      'Realistic values from the subject; "answer" is a plain number in "unit"; "tolerance" is relative (0.01-0.05); '
      'solution steps show formulas in LaTeX and the numbers inserted. Double-check the arithmetic.';
  @override
  Map<String, Object?>? get jsonSchema => _objectSchema(id, {
    'problem': _str,
    'given': {
      'type': 'array',
      'items': _closed({'symbol': _str, 'value': _str, 'unit': _str}),
    },
    'asked': _str,
    'answer': {'type': 'number'},
    'unit': _str,
    'tolerance': {'type': 'number'},
    'hint': _str,
    'solution': _strList,
  });
  @override
  Map<String, dynamic>? normalize(Map<String, dynamic> raw) {
    final problem = _clean(raw['problem'] ?? raw['question']);
    final answer = parseNumber(raw['answer']);
    if (problem.isEmpty || answer == null || !answer.isFinite) return null;
    final given = <Map<String, dynamic>>[];
    for (final g in (raw['given'] is List ? raw['given'] as List : const [])) {
      final m = jMap(g);
      final symbol = _clean(m['symbol'] ?? m['name']);
      if (symbol.isEmpty) continue;
      given.add({'symbol': symbol, 'value': _clean(m['value']), 'unit': _clean(m['unit'])});
    }
    return {
      'problem': problem,
      'given': given.take(10).toList(),
      'asked': _clean(raw['asked'] ?? raw['find']),
      'answer': answer,
      'unit': _clean(raw['unit']),
      'tolerance': (parseNumber(raw['tolerance']) ?? 0.02).abs().clamp(0.001, 0.25),
      'hint': _clean(raw['hint']),
      'solution': _cleanList(raw['solution'] ?? raw['steps']).take(10).toList(),
    };
  }
}

/// Reel types that are shown on the neutral "math" background.
const mathReelTypes = {'math_recipe', 'theorem', 'formula', 'calc_exercise'};

/// Registry of all reel types.
class ReelTypes {
  static const List<ReelTypeSpec> all = [
    ExplainerSpec(),
    KeyPointsSpec(),
    QuizSpec(),
    TrueFalseSpec(),
    FlashcardSpec(),
    ClozeSpec(),
    WriteRecallSpec(),
    MnemonicSpec(),
    VisualReelSpec(),
    MathRecipeSpec(),
    TheoremSpec(),
    FormulaCardSpec(),
    CalcExerciseSpec(),
  ];

  static final Map<String, ReelTypeSpec> _byId = {for (final t in all) t.id: t};

  static ReelTypeSpec? byId(String id) => _byId[id];

  static List<String> get ids => all.map((t) => t.id).toList();
}
