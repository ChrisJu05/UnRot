import 'package:material_ui/material_ui.dart';

import '../../core/util/ids.dart';

class AppTheme {
  /// Monospace text. Named fonts first: on some Linux setups the generic
  /// "monospace" resolves to a CJK font that draws backslashes as "¥".
  static const monoStyle = TextStyle(
    fontFamily: 'DejaVu Sans Mono',
    fontFamilyFallback: ['Menlo', 'Consolas', 'Liberation Mono', 'Noto Sans Mono', 'Courier New', 'monospace'],
  );

  static const seed = Color(0xFF7C4DFF);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF0E0E12));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0E0E12),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A22),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF121218), height: 68),
      navigationRailTheme: const NavigationRailThemeData(backgroundColor: Color(0xFF121218)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0E0E12), centerTitle: false),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Background gradients for reels; picked deterministically per section.
  static const List<List<Color>> reelGradients = [
    [Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)],
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    [Color(0xFF1D2B64), Color(0xFF6A3093), Color(0xFFA044FF)],
    [Color(0xFF134E5E), Color(0xFF2B7A6F), Color(0xFF71B280)],
    [Color(0xFF42275A), Color(0xFF734B6D), Color(0xFFB06AB3)],
    [Color(0xFF232526), Color(0xFF414345), Color(0xFF5B5E62)],
    [Color(0xFF16222A), Color(0xFF3A6073), Color(0xFF5D8AA8)],
    [Color(0xFF4B1248), Color(0xFF9D2C5E), Color(0xFFF0C27B)],
  ];

  /// Calm slate background for formula-heavy reels.
  static const List<Color> neutralGradient = [Color(0xFF1B2026), Color(0xFF232A31), Color(0xFF2B333B)];

  static List<Color> gradientFor(String key) => reelGradients[stableHash(key) % reelGradients.length];

  static const Map<String, IconData> reelIcons = {
    'explainer': Icons.lightbulb_outline,
    'key_points': Icons.format_list_bulleted,
    'quiz': Icons.quiz_outlined,
    'true_false': Icons.rule,
    'flashcard': Icons.style_outlined,
    'cloze': Icons.text_fields,
    'write_recall': Icons.draw_outlined,
    'mnemonic': Icons.psychology_alt_outlined,
    'visual': Icons.auto_graph,
    'math_recipe': Icons.format_list_numbered,
    'theorem': Icons.gavel_outlined,
    'formula': Icons.functions,
    'calc_exercise': Icons.calculate_outlined,
  };

  static const Map<String, IconData> modeIcons = {
    'linear': Icons.route_outlined,
    'exam': Icons.event_available_outlined,
    'rote': Icons.repeat,
    'explore': Icons.shuffle,
  };
}
