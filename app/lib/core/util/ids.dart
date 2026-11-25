import 'dart:math';

final Random _random = Random.secure();

/// Generates a short, collision-resistant, URL/file-name safe id.
///
/// Format: `<prefix><millis base36><8 random base36 chars>`.
String newId([String prefix = '']) {
  final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = List.generate(8, (_) => _random.nextInt(36).toRadixString(36)).join();
  return '$prefix$time$rand';
}

/// Stable 32-bit FNV-1a hash of a string (used for deterministic seeds/colors).
int stableHash(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
