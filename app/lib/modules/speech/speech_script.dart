import '../../core/models/reel.dart';
import '../../core/util/json.dart';

/// Turns reels into text that sounds natural when read aloud, including
/// formulas (LaTeX → "a over b", "x squared", "Integral von 0 bis 1" …).
class SpeechScript {
  static const _languageCodes = {
    'English': 'en-US',
    'Deutsch': 'de-DE',
    'Español': 'es-ES',
    'Français': 'fr-FR',
    'Italiano': 'it-IT',
    'Português': 'pt-PT',
    'Nederlands': 'nl-NL',
    'Polski': 'pl-PL',
    'Türkçe': 'tr-TR',
    'Українська': 'uk-UA',
    '中文': 'zh-CN',
    '日本語': 'ja-JP',
  };

  static final _germanWords = RegExp(
    r'\b(der|die|das|und|ist|nicht|eine|einer|mit|für|wird|sind|auf|bei|wenn|dass|sich|auch|oder|von|zu)\b',
    caseSensitive: false,
  );
  static final _englishWords = RegExp(
    r'\b(the|and|is|not|with|for|are|on|when|that|this|of|to|from|or|which)\b',
    caseSensitive: false,
  );

  /// BCP-47 code for the reel's language (detects German/English for "source").
  static String languageCode(Reel reel) {
    final code = _languageCodes[reel.language];
    if (code != null) return code;
    final text = _allText(reel.data);
    return _germanWords.allMatches(text).length > _englishWords.allMatches(text).length ? 'de-DE' : 'en-US';
  }

  static String _allText(Object? v) => switch (v) {
    String s => s,
    List l => l.map(_allText).join(' '),
    Map m => m.values.map(_allText).join(' '),
    _ => '',
  };

  /// The text to speak for a reel.
  static String forReel(Reel reel) {
    final de = languageCode(reel).startsWith('de');
    String t(String key) => clean(reel.str(key), german: de);
    final parts = <String>[];
    void add(String? s) {
      if (s != null && s.trim().isNotEmpty) parts.add(s.trim());
    }

    switch (reel.type) {
      case 'explainer':
        add(t('title'));
        add(t('body'));
        if (reel.str('takeaway').isNotEmpty) add('${de ? 'Kernaussage' : 'Key takeaway'}: ${t('takeaway')}');
      case 'key_points':
        add(t('title'));
        final points = reel.list('points');
        for (var i = 0; i < points.length; i++) {
          add('${i + 1}: ${clean(points[i], german: de)}');
        }
      case 'quiz':
        add(t('question'));
        final options = reel.list('options');
        for (var i = 0; i < options.length; i++) {
          add('${de ? 'Antwort' : 'Option'} ${String.fromCharCode(65 + i)}: ${clean(options[i], german: de)}');
        }
      case 'true_false':
        add(de ? 'Richtig oder falsch?' : 'True or false?');
        add(t('statement'));
      case 'flashcard':
        add(t('front'));
      case 'cloze':
        add(clean(reel.str('text').replaceAll('____', de ? ' Lücke ' : ' blank '), german: de));
      case 'write_recall':
        add(t('prompt'));
      case 'mnemonic':
        add(t('concept'));
        add(t('hook'));
        add(t('explanation'));
      case 'visual':
        add(t('title'));
        add(t('caption'));
        final visual = jMap(reel.data['visual']);
        if (visual['kind'] == 'equation') {
          add(latexToSpeech(jString(visual['latex']), german: de));
          for (final s in (visual['steps'] is List ? visual['steps'] as List : const [])) {
            add(latexToSpeech(jString(jMap(s)['latex']), german: de));
            add(clean(jString(jMap(s)['note']), german: de));
          }
        } else if (visual['kind'] == 'image') {
          add(clean(jString(visual['alt']), german: de));
        }
      case 'math_recipe':
        add(t('title'));
        if (reel.str('goal').isNotEmpty) add('${de ? 'Ziel' : 'Goal'}: ${t('goal')}');
        final steps = reel.data['steps'] is List ? reel.data['steps'] as List : const [];
        for (var i = 0; i < steps.length; i++) {
          final s = jMap(steps[i]);
          add('${de ? 'Schritt' : 'Step'} ${i + 1}: ${clean(jString(s['action']), german: de)}');
          if (jString(s['latex']).isNotEmpty) add(latexToSpeech(jString(s['latex']), german: de));
        }
      case 'theorem':
        add('${reel.str('kind')}: ${t('name')}');
        final assumptions = reel.list('assumptions');
        if (assumptions.isNotEmpty) {
          add('${de ? 'Voraussetzungen' : 'Assumptions'}: ${assumptions.map((a) => clean(a, german: de)).join('; ')}');
        }
        add(de ? 'Wie lautet die Aussage?' : 'What does it state?');
      case 'formula':
        add(t('name'));
        add(latexToSpeech(reel.str('latex'), german: de));
      case 'calc_exercise':
        add(t('problem'));
        final given = reel.data['given'] is List ? reel.data['given'] as List : const [];
        if (given.isNotEmpty) {
          add(
            '${de ? 'Gegeben' : 'Given'}: ${given.map((g) {
              final m = jMap(g);
              return '${latexToSpeech(jString(m['symbol']), german: de)} ${de ? 'gleich' : 'equals'} ${jString(m['value'])} ${unit(jString(m['unit']), german: de)}';
            }).join('; ')}',
          );
        }
        if (reel.str('asked').isNotEmpty) add('${de ? 'Gesucht' : 'Find'}: ${t('asked')}');
      default:
        add(clean(reel.summary, german: de));
    }
    return _join(parts);
  }

  static String _join(List<String> parts) => parts.map((p) => RegExp(r'[.!?:;]$').hasMatch(p) ? p : '$p.').join(' ');

  /// What is hidden at first (answer, back side, solution); null for reels
  /// without a hidden part. [correct] adds "Correct!"/"Not quite." in front.
  static String? answerFor(Reel reel, {bool? correct}) {
    final de = languageCode(reel).startsWith('de');
    String t(String key) => clean(reel.str(key), german: de);
    final parts = <String>[];
    void add(String? s) {
      if (s != null && s.trim().isNotEmpty) parts.add(s.trim());
    }

    switch (reel.type) {
      case 'quiz':
        final options = reel.list('options');
        final i = jInt(reel.data['answer_index'], -1);
        if (i < 0 || i >= options.length) return null;
        add('${de ? 'Richtig ist' : 'The answer is'} ${String.fromCharCode(65 + i)}: ${clean(options[i], german: de)}');
        add(t('explanation'));
      case 'true_false':
        add(
          reel.data['answer'] == true
              ? (de ? 'Die Aussage ist richtig' : 'It is true')
              : (de ? 'Die Aussage ist falsch' : 'It is false'),
        );
        add(t('explanation'));
      case 'flashcard':
        add(t('back'));
      case 'cloze':
        add(clean(reel.str('text').replaceAll('____', reel.str('answer')), german: de));
      case 'write_recall':
        add(t('model_answer'));
      case 'theorem':
        add(t('statement'));
        if (reel.str('formula').isNotEmpty) add(latexToSpeech(reel.str('formula'), german: de));
        if (reel.str('intuition').isNotEmpty) add('${de ? 'Intuition' : 'Intuition'}: ${t('intuition')}');
      case 'formula':
        final symbols = reel.data['symbols'] is List ? reel.data['symbols'] as List : const [];
        if (symbols.isEmpty) return null;
        for (final s in symbols) {
          final m = jMap(s);
          add('${latexToSpeech(jString(m['symbol']), german: de)}: ${clean(jString(m['meaning']), german: de)}');
        }
      case 'calc_exercise':
        final u = unit(reel.str('unit'), german: de);
        add('${de ? 'Ergebnis' : 'Result'}: ${_number(jDouble(reel.data['answer']), de)} $u'.trim());
        final solution = reel.list('solution');
        if (solution.isNotEmpty) add(solution.map((l) => clean(l, german: de)).join('. '));
      default:
        return null;
    }
    if (parts.isEmpty) return null;
    if (correct != null) {
      parts.insert(0, correct ? (de ? 'Richtig!' : 'Correct!') : (de ? 'Nicht ganz.' : 'Not quite.'));
    }
    return _join(parts);
  }

  /// Speaks a unit: `\Omega` → "Omega", `m/s` → "m per s".
  static String unit(String u, {bool german = false}) =>
      latexToSpeech(u, german: german).replaceAll(german ? ' durch ' : ' over ', german ? ' pro ' : ' per ');

  static String _number(double v, bool german) {
    String trim(String n) => n.contains('.') ? n.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : n;
    var s = v == v.roundToDouble() && v.abs() < 1e15 ? v.toStringAsFixed(0) : v.toStringAsPrecision(4);
    final m = RegExp(r'^(-?[\d.]+)e([+-]?\d+)$').firstMatch(s);
    if (m != null) {
      s = '${trim(m[1]!)} ${german ? 'mal 10 hoch' : 'times 10 to the power of'} ${int.parse(m[2]!)}';
    } else {
      s = trim(s);
    }
    return german ? s.replaceAll('.', ',') : s;
  }

  /// Removes markdown/emojis and speaks inline math.
  static String clean(String text, {bool german = false}) {
    var s = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]+?)\$\$|\$([^$]+)\$|\\\(([\s\S]+?)\\\)'),
      (m) => ' ${latexToSpeech(m[1] ?? m[2] ?? m[3]!, german: german)} ',
    );
    s = s.replaceAll(RegExp(r'\*\*|__|`'), '');
    s = s.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _greek = {
    'alpha': 'alpha',
    'beta': 'beta',
    'gamma': 'gamma',
    'delta': 'delta',
    'epsilon': 'epsilon',
    'varepsilon': 'epsilon',
    'zeta': 'zeta',
    'eta': 'eta',
    'theta': 'theta',
    'vartheta': 'theta',
    'kappa': 'kappa',
    'lambda': 'lambda',
    'mu': 'mü',
    'nu': 'nü',
    'xi': 'xi',
    'pi': 'pi',
    'rho': 'rho',
    'sigma': 'sigma',
    'tau': 'tau',
    'phi': 'phi',
    'varphi': 'phi',
    'chi': 'chi',
    'psi': 'psi',
    'omega': 'omega',
    'Gamma': 'Gamma',
    'Delta': 'Delta',
    'Theta': 'Theta',
    'Lambda': 'Lambda',
    'Sigma': 'Sigma',
    'Phi': 'Phi',
    'Psi': 'Psi',
    'Omega': 'Omega',
  };

  /// Converts LaTeX into speakable words.
  static String latexToSpeech(String latex, {bool german = false}) {
    String w(String en, String de) => german ? de : en;
    var s = latex.trim();
    // Formatting commands: keep the content.
    s = s.replaceAllMapped(
      RegExp(r'\\(?:mathrm|text|textrm|mathbf|mathit|operatorname|boldsymbol|mathcal|mathbb)\{([^{}]*)\}'),
      (m) => ' ${m[1]} ',
    );
    s = s.replaceAll(RegExp(r'\\(left|right|big|Big|bigg|Bigg)'), '');
    s = s.replaceAll(RegExp(r'\\[,;:! ]|\\quad|\\qquad|~'), ' ');
    // Structures, innermost first.
    for (var i = 0; i < 6; i++) {
      final before = s;
      s = s.replaceAllMapped(
        RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}'),
        (m) => ' ${m[1]} ${w('over', 'durch')} ${m[2]} ',
      );
      s = s.replaceAllMapped(
        RegExp(r'\\sqrt\[([^\]]*)\]\{([^{}]*)\}'),
        (m) => ' ${w('${m[1]}th root of', '${m[1]}-te Wurzel aus')} ${m[2]} ',
      );
      s = s.replaceAllMapped(RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => ' ${w('square root of', 'Wurzel aus')} ${m[1]} ');
      s = s.replaceAllMapped(
        RegExp(r'\\(vec|overrightarrow)\{([^{}]*)\}'),
        (m) => ' ${w('vector', 'Vektor')} ${m[2]} ',
      );
      s = s.replaceAllMapped(RegExp(r'\\hat\{([^{}]*)\}'), (m) => ' ${m[1]} ${w('hat', 'Dach')} ');
      s = s.replaceAllMapped(RegExp(r'\\dot\{([^{}]*)\}'), (m) => ' ${m[1]} ${w('dot', 'Punkt')} ');
      s = s.replaceAllMapped(RegExp(r'\\(?:bar|overline)\{([^{}]*)\}'), (m) => ' ${m[1]} ${w('bar', 'quer')} ');
      if (s == before) break;
    }
    // Big operators with limits.
    s = s.replaceAllMapped(RegExp(r'\\(int|oint|sum|prod)_\{?([^{}^ ]*)\}?\^\{?([^{} ]*)\}?'), (m) {
      final op = {
        'int': w('integral', 'Integral'),
        'oint': w('closed integral', 'Ringintegral'),
        'sum': w('sum', 'Summe'),
        'prod': w('product', 'Produkt'),
      }[m[1]]!;
      return ' $op ${w('from', 'von')} ${m[2]} ${w('to', 'bis')} ${m[3]} ';
    });
    s = s.replaceAllMapped(RegExp(r'\\lim_\{([^{}]*)\}'), (m) => ' ${w('limit as', 'Grenzwert für')} ${m[1]} ');
    // Powers.
    s = s.replaceAllMapped(RegExp(r'\^\{?2\}?(?![0-9])'), (_) => ' ${w('squared', 'Quadrat')} ');
    s = s.replaceAllMapped(RegExp(r'\^\{?3\}?(?![0-9])'), (_) => ' ${w('cubed', 'hoch 3')} ');
    s = s.replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'), (m) => ' ${w('to the power of', 'hoch')} ${m[1]} ');
    s = s.replaceAllMapped(RegExp(r'\^(\S)'), (m) => ' ${w('to the power of', 'hoch')} ${m[1]} ');
    // Subscripts: just read them after the symbol.
    s = s.replaceAllMapped(RegExp(r'_\{([^{}]*)\}'), (m) => ' ${m[1]} ');
    s = s.replaceAllMapped(RegExp(r'_(\S)'), (m) => ' ${m[1]} ');
    // Symbols.
    final symbols = <String, String>{
      r'\cdot': w('times', 'mal'),
      r'\times': w('times', 'mal'),
      r'\pm': w('plus or minus', 'plus minus'),
      r'\approx': w('approximately', 'ungefähr'),
      r'\neq': w('is not equal to', 'ungleich'),
      r'\ne': w('is not equal to', 'ungleich'),
      r'\leq': w('less than or equal to', 'kleiner gleich'),
      r'\le': w('less than or equal to', 'kleiner gleich'),
      r'\geq': w('greater than or equal to', 'größer gleich'),
      r'\ge': w('greater than or equal to', 'größer gleich'),
      r'\to': w('to', 'gegen'),
      r'\rightarrow': w('to', 'gegen'),
      r'\Rightarrow': w('implies', 'daraus folgt'),
      r'\Leftrightarrow': w('if and only if', 'genau dann wenn'),
      r'\infty': w('infinity', 'unendlich'),
      r'\partial': w('partial', 'partiell'),
      r'\nabla': 'nabla',
      r'\propto': w('is proportional to', 'proportional zu'),
      r'\in': w('in', 'aus'),
      r'\int': w('integral of', 'Integral über'),
      r'\sum': w('sum of', 'Summe über'),
      r'\sin': 'sinus',
      r'\cos': 'cosinus',
      r'\tan': 'tangens',
      r'\exp': 'exp',
      r'\ln': w('natural log of', 'Logarithmus naturalis von'),
      r'\log': 'log',
      r'\degree': w('degrees', 'Grad'),
      r'\%': w('percent', 'Prozent'),
    };
    final keys = symbols.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      s = s.replaceAll(RegExp('${RegExp.escape(k)}(?![A-Za-z])'), ' ${symbols[k]} ');
    }
    s = s.replaceAllMapped(RegExp(r'\\([A-Za-z]+)'), (m) => ' ${_greek[m[1]] ?? m[1]} ');
    s = s
        .replaceAll('=', ' ${w('equals', 'gleich')} ')
        .replaceAll('<', ' ${w('is less than', 'kleiner als')} ')
        .replaceAll('>', ' ${w('is greater than', 'größer als')} ')
        .replaceAll('+', ' plus ')
        .replaceAll(RegExp(r'(?<=\s|^)-|(?<=\S)-(?=\S)|−'), ' minus ')
        .replaceAll('/', ' ${w('over', 'durch')} ')
        .replaceAll('*', ' ${w('times', 'mal')} ');
    s = s.replaceAll(RegExp(r'[{}\\^_&]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
