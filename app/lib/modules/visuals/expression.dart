import 'dart:math' as math;

/// A small, safe math expression language used by interactive visuals.
///
/// Supports numbers, variables, `+ - * / % ^` (also `**`, `·`, `×`, `−`),
/// implicit multiplication (`2x`, `3(x+1)`), comparisons and logic
/// (`< <= > >= == != && || !`), the ternary `c ? a : b`, constants `pi`/`π`/`e`
/// and common functions (sin, cos, tan, exp, ln, log, sqrt, abs, min, max,
/// if, clamp, ...). Nothing outside pure arithmetic can be executed.
class ExprException implements Exception {
  ExprException(this.message);
  final String message;
  @override
  String toString() => 'ExprException: $message';
}

abstract class Expr {
  const Expr();
  double eval(Map<String, double> vars);
  void collectVariables(Set<String> out);

  Set<String> get variables {
    final out = <String>{};
    collectVariables(out);
    return out;
  }
}

class _Num extends Expr {
  const _Num(this.value);
  final double value;
  @override
  double eval(Map<String, double> vars) => value;
  @override
  void collectVariables(Set<String> out) {}
}

class _Var extends Expr {
  const _Var(this.name);
  final String name;
  @override
  double eval(Map<String, double> vars) {
    final v = vars[name];
    if (v != null) return v;
    return switch (name) {
      'pi' || 'π' => math.pi,
      'e' => math.e,
      'tau' || 'τ' => 2 * math.pi,
      'inf' || 'infinity' => double.infinity,
      _ => double.nan,
    };
  }

  @override
  void collectVariables(Set<String> out) {
    if (!Expression.constants.contains(name)) out.add(name);
  }
}

class _Unary extends Expr {
  const _Unary(this.op, this.operand);
  final String op;
  final Expr operand;
  @override
  double eval(Map<String, double> vars) {
    final v = operand.eval(vars);
    return switch (op) {
      '-' => -v,
      '!' => v == 0 ? 1 : 0,
      _ => v,
    };
  }

  @override
  void collectVariables(Set<String> out) => operand.collectVariables(out);
}

class _Binary extends Expr {
  const _Binary(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;

  static double _b(bool v) => v ? 1 : 0;

  @override
  double eval(Map<String, double> vars) {
    if (op == '&&') return _b(left.eval(vars) != 0 && right.eval(vars) != 0);
    if (op == '||') return _b(left.eval(vars) != 0 || right.eval(vars) != 0);
    final a = left.eval(vars), b = right.eval(vars);
    return switch (op) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' => a / b,
      '%' => a % b,
      '^' => _pow(a, b),
      '<' => _b(a < b),
      '<=' => _b(a <= b),
      '>' => _b(a > b),
      '>=' => _b(a >= b),
      '==' => _b((a - b).abs() < 1e-9),
      '!=' => _b((a - b).abs() >= 1e-9),
      _ => double.nan,
    };
  }

  static double _pow(double a, double b) {
    // Real odd roots of negative numbers, e.g. (-8)^(1/3) = -2.
    if (a < 0 && b != b.roundToDouble()) {
      final inv = 1 / b;
      if ((inv - inv.round()).abs() < 1e-9 && inv.round().isOdd) return -math.pow(-a, b).toDouble();
    }
    return math.pow(a, b).toDouble();
  }

  @override
  void collectVariables(Set<String> out) {
    left.collectVariables(out);
    right.collectVariables(out);
  }
}

class _Ternary extends Expr {
  const _Ternary(this.cond, this.a, this.b);
  final Expr cond, a, b;
  @override
  double eval(Map<String, double> vars) => cond.eval(vars) != 0 ? a.eval(vars) : b.eval(vars);
  @override
  void collectVariables(Set<String> out) {
    cond.collectVariables(out);
    a.collectVariables(out);
    b.collectVariables(out);
  }
}

class _Call extends Expr {
  const _Call(this.name, this.args);
  final String name;
  final List<Expr> args;

  @override
  double eval(Map<String, double> vars) {
    if (name == 'if' && args.length == 3) {
      return args[0].eval(vars) != 0 ? args[1].eval(vars) : args[2].eval(vars);
    }
    final v = [for (final a in args) a.eval(vars)];
    double a0() => v.isEmpty ? double.nan : v[0];
    double a1() => v.length < 2 ? double.nan : v[1];
    return switch (name) {
      'sin' => math.sin(a0()),
      'cos' => math.cos(a0()),
      'tan' => math.tan(a0()),
      'cot' => 1 / math.tan(a0()),
      'sec' => 1 / math.cos(a0()),
      'csc' => 1 / math.sin(a0()),
      'asin' || 'arcsin' => math.asin(a0()),
      'acos' || 'arccos' => math.acos(a0()),
      'atan' || 'arctan' => v.length == 2 ? math.atan2(a0(), a1()) : math.atan(a0()),
      'atan2' => math.atan2(a0(), a1()),
      'sinh' => (math.exp(a0()) - math.exp(-a0())) / 2,
      'cosh' => (math.exp(a0()) + math.exp(-a0())) / 2,
      'tanh' => _tanh(a0()),
      'exp' => math.exp(a0()),
      'ln' => math.log(a0()),
      'log' => v.length == 2 ? math.log(a0()) / math.log(a1()) : math.log(a0()) / math.ln10,
      'log10' || 'lg' => math.log(a0()) / math.ln10,
      'log2' || 'lb' => math.log(a0()) / math.ln2,
      'sqrt' => math.sqrt(a0()),
      'cbrt' => a0() < 0 ? -math.pow(-a0(), 1 / 3).toDouble() : math.pow(a0(), 1 / 3).toDouble(),
      'abs' => a0().abs(),
      'floor' => a0().floorToDouble(),
      'ceil' => a0().ceilToDouble(),
      'round' => a0().roundToDouble(),
      'sign' || 'sgn' => a0().sign,
      'min' => v.isEmpty ? double.nan : v.reduce(math.min),
      'max' => v.isEmpty ? double.nan : v.reduce(math.max),
      'pow' => _Binary._pow(a0(), a1()),
      'mod' => a0() % a1(),
      'clamp' => v.length == 3 ? v[0].clamp(math.min(v[1], v[2]), math.max(v[1], v[2])).toDouble() : double.nan,
      'deg' => a0() * 180 / math.pi,
      'rad' => a0() * math.pi / 180,
      'fact' || 'factorial' => _factorial(a0()),
      'step' || 'heaviside' => a0() >= 0 ? 1 : 0,
      _ => double.nan,
    };
  }

  static double _tanh(double x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final e2 = math.exp(2 * x);
    return (e2 - 1) / (e2 + 1);
  }

  static double _factorial(double x) {
    if (x < 0 || x != x.roundToDouble() || x > 170) return double.nan;
    var r = 1.0;
    for (var i = 2; i <= x; i++) {
      r *= i;
    }
    return r;
  }

  @override
  void collectVariables(Set<String> out) {
    for (final a in args) {
      a.collectVariables(out);
    }
  }
}

class _Token {
  const _Token(this.type, this.text, [this.number = 0]);
  final String type; // num, id, op, end
  final String text;
  final double number;
  @override
  String toString() => text;
}

class Expression {
  static const constants = {'pi', 'π', 'e', 'tau', 'τ', 'inf', 'infinity'};
  static const functions = {
    'sin',
    'cos',
    'tan',
    'cot',
    'sec',
    'csc',
    'asin',
    'arcsin',
    'acos',
    'arccos',
    'atan',
    'arctan',
    'atan2',
    'sinh',
    'cosh',
    'tanh',
    'exp',
    'ln',
    'log',
    'log10',
    'lg',
    'log2',
    'lb',
    'sqrt',
    'cbrt',
    'abs',
    'floor',
    'ceil',
    'round',
    'sign',
    'sgn',
    'min',
    'max',
    'pow',
    'mod',
    'clamp',
    'deg',
    'rad',
    'fact',
    'factorial',
    'step',
    'heaviside',
    'if',
  };

  static final Map<String, Expr> _cache = {};

  /// Parses [source] (cached). Throws [ExprException] on syntax errors.
  static Expr parse(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    final parser = _Parser(_tokenize(source));
    final expr = parser.parseExpression();
    if (parser.peek.type != 'end') throw ExprException('Unexpected "${parser.peek.text}" in "$source"');
    if (_cache.length > 2000) _cache.clear();
    return _cache[source] = expr;
  }

  static Expr? tryParse(String source) {
    try {
      return parse(source);
    } on ExprException {
      return null;
    }
  }

  /// Evaluates [source]; returns NaN for invalid expressions.
  static double eval(String source, Map<String, double> vars) {
    final e = tryParse(source);
    return e == null ? double.nan : e.eval(vars);
  }

  static List<_Token> _tokenize(String input) {
    final s = input
        .replaceAll('−', '-')
        .replaceAll('·', '*')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('**', '^')
        .replaceAll('≤', '<=')
        .replaceAll('≥', '>=')
        .replaceAll('≠', '!=');
    final tokens = <_Token>[];
    var i = 0;
    final idStart = RegExp(r'[A-Za-z_Ͱ-Ͽ]');
    final idPart = RegExp(r'[A-Za-z0-9_Ͱ-Ͽ]');
    while (i < s.length) {
      final c = s[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        final m = RegExp(r'(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?').matchAsPrefix(s, i);
        if (m == null) throw ExprException('Bad number at $i in "$input"');
        tokens.add(_Token('num', m[0]!, double.parse(m[0]!)));
        i = m.end;
        continue;
      }
      if (idStart.hasMatch(c)) {
        var j = i + 1;
        while (j < s.length && idPart.hasMatch(s[j])) {
          j++;
        }
        tokens.add(_Token('id', s.substring(i, j)));
        i = j;
        continue;
      }
      final two = i + 1 < s.length ? s.substring(i, i + 2) : '';
      if (const {'<=', '>=', '==', '!=', '&&', '||'}.contains(two)) {
        tokens.add(_Token('op', two));
        i += 2;
        continue;
      }
      if ('+-*/%^()<>!,?:|'.contains(c)) {
        tokens.add(_Token('op', c));
        i++;
        continue;
      }
      if (c == '=') {
        // A single "=" is treated as equality.
        tokens.add(const _Token('op', '=='));
        i++;
        continue;
      }
      throw ExprException('Unexpected character "$c" in "$input"');
    }
    tokens.add(const _Token('end', ''));
    return tokens;
  }
}

class _Parser {
  _Parser(this.tokens);
  final List<_Token> tokens;
  int pos = 0;
  int depth = 0;

  _Token get peek => tokens[pos];
  _Token next() => tokens[pos++];
  bool isOp(String op) => peek.type == 'op' && peek.text == op;

  void expect(String op) {
    if (!isOp(op)) throw ExprException('Expected "$op" but found "${peek.text}"');
    pos++;
  }

  Expr parseExpression() {
    if (++depth > 200) throw ExprException('Expression too deeply nested');
    try {
      final cond = _or();
      if (isOp('?')) {
        pos++;
        final a = parseExpression();
        expect(':');
        final b = parseExpression();
        return _Ternary(cond, a, b);
      }
      return cond;
    } finally {
      depth--;
    }
  }

  Expr _or() {
    var left = _and();
    while (isOp('||')) {
      pos++;
      left = _Binary('||', left, _and());
    }
    return left;
  }

  Expr _and() {
    var left = _cmp();
    while (isOp('&&')) {
      pos++;
      left = _Binary('&&', left, _cmp());
    }
    return left;
  }

  Expr _cmp() {
    var left = _add();
    while (peek.type == 'op' && const {'<', '<=', '>', '>=', '==', '!='}.contains(peek.text)) {
      final op = next().text;
      left = _Binary(op, left, _add());
    }
    return left;
  }

  Expr _add() {
    var left = _mul();
    while (isOp('+') || isOp('-')) {
      final op = next().text;
      left = _Binary(op, left, _mul());
    }
    return left;
  }

  bool get _startsImplicitFactor => peek.type == 'num' || peek.type == 'id' || (peek.type == 'op' && peek.text == '(');

  Expr _mul() {
    var left = _unary();
    while (true) {
      if (isOp('*') || isOp('/') || isOp('%')) {
        final op = next().text;
        left = _Binary(op, left, _unary());
      } else if (_startsImplicitFactor) {
        left = _Binary('*', left, _power());
      } else {
        return left;
      }
    }
  }

  Expr _unary() {
    if (isOp('-') || isOp('+') || isOp('!')) {
      final op = next().text;
      return _Unary(op, _unary());
    }
    return _power();
  }

  Expr _power() {
    final base = _primary();
    if (isOp('^')) {
      pos++;
      return _Binary('^', base, _unary());
    }
    return base;
  }

  Expr _primary() {
    final t = next();
    if (t.type == 'num') return _Num(t.number);
    if (t.type == 'id') {
      if (isOp('(') && Expression.functions.contains(t.text)) {
        pos++;
        final args = <Expr>[];
        if (!isOp(')')) {
          args.add(parseExpression());
          while (isOp(',')) {
            pos++;
            args.add(parseExpression());
          }
        }
        expect(')');
        return _Call(t.text, args);
      }
      return _Var(t.text);
    }
    if (t.type == 'op' && t.text == '(') {
      final e = parseExpression();
      expect(')');
      return e;
    }
    if (t.type == 'op' && t.text == '|') {
      final e = parseExpression();
      expect('|');
      return _Call('abs', [e]);
    }
    throw ExprException(t.type == 'end' ? 'Unexpected end of expression' : 'Unexpected "${t.text}"');
  }
}

/// Formats a number compactly for labels and SVG attributes.
String formatNumber(double v, {int decimals = 3}) {
  if (v.isNaN) return '–';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s == '-0' ? '0' : s;
}
