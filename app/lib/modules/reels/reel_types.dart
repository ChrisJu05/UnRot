import '../../core/util/json.dart';
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
  ];

  static final Map<String, ReelTypeSpec> _byId = {for (final t in all) t.id: t};

  static ReelTypeSpec? byId(String id) => _byId[id];

  static List<String> get ids => all.map((t) => t.id).toList();
}
