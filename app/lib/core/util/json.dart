/// Small helpers for tolerant JSON (de)serialisation of persisted models.
///
/// Persisted data may come from older app versions, so every reader falls back
/// to a sensible default instead of throwing.
library;

String jString(Object? v, [String fallback = '']) => v is String ? v : (v == null ? fallback : v.toString());

String? jStringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

int jInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double jDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool jBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true';
  return fallback;
}

DateTime? jDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<String> jStringList(Object? v) =>
    v is List ? v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList() : <String>[];

Map<String, dynamic> jMap(Object? v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

Map<String, double> jDoubleMap(Object? v) => jMap(v).map((k, val) => MapEntry(k, jDouble(val)));
