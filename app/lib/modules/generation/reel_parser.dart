import 'dart:convert';

import '../../core/models/reel.dart';
import '../../core/util/ids.dart';
import '../../core/util/json.dart';
import '../reels/reel_types.dart';
import 'generation_job.dart';

/// Parses (possibly messy) model output into validated [Reel]s.
class ReelParser {
  const ReelParser();

  /// Extracts the first JSON value from [text], tolerating code fences and prose.
  static Object? extractJson(String text) {
    var t = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = fence.group(1)!.trim();
    try {
      return jsonDecode(t);
    } catch (_) {}
    // Find the outermost {...} or [...] by bracket matching.
    for (final open in ['{', '[']) {
      final start = t.indexOf(open);
      if (start < 0) continue;
      final close = open == '{' ? '}' : ']';
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < t.length; i++) {
        final c = t[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (c == r'\') {
            escaped = true;
          } else if (c == '"') {
            inString = false;
          }
          continue;
        }
        if (c == '"') {
          inString = true;
        } else if (c == open) {
          depth++;
        } else if (c == close) {
          depth--;
          if (depth == 0) {
            try {
              return jsonDecode(t.substring(start, i + 1));
            } catch (_) {
              break;
            }
          }
        }
      }
      // Truncated output: salvage complete reel objects from the array.
      final salvaged = _salvageObjects(t.substring(start));
      if (salvaged.isNotEmpty) return {'reels': salvaged};
    }
    return null;
  }

  static List<Object?> _salvageObjects(String t) {
    final arrayStart = t.indexOf('[');
    if (arrayStart < 0) return const [];
    final result = <Object?>[];
    var depth = 0;
    var objStart = -1;
    var inString = false;
    var escaped = false;
    for (var i = arrayStart + 1; i < t.length; i++) {
      final c = t[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        if (depth == 0) objStart = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && objStart >= 0) {
          try {
            result.add(jsonDecode(t.substring(objStart, i + 1)));
          } catch (_) {}
          objStart = -1;
        }
      }
    }
    return result;
  }

  List<Reel> parse(String text, GenerationJob job, {required String generator}) {
    final json = extractJson(text);
    final List rawList;
    if (json is List) {
      rawList = json;
    } else if (json is Map && json['reels'] is List) {
      rawList = json['reels'] as List;
    } else if (json is Map && json['type'] is String) {
      rawList = [json];
    } else {
      return const [];
    }
    final allowed = job.reelTypes.toSet();
    final reels = <Reel>[];
    for (var i = 0; i < rawList.length; i++) {
      final raw = jMap(rawList[i]);
      var type = jString(raw['type']).toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
      if (type == 'multiple_choice' || type == 'mcq') type = 'quiz';
      if (type == 'truefalse') type = 'true_false';
      if (type.isEmpty && i < job.reelTypes.length) type = job.reelTypes[i];
      final spec = ReelTypes.byId(type);
      if (spec == null || (allowed.isNotEmpty && !allowed.contains(type) && job.focus == null)) continue;
      final data = spec.normalize(raw);
      if (data == null) continue;
      reels.add(
        Reel(
          id: newId('r'),
          sourceId: job.source.id,
          chunkId: job.chunk.id,
          type: type,
          data: data,
          createdAt: DateTime.now(),
          generator: generator,
          difficulty: job.difficulty,
          parentReelId: job.parentReelId,
        ),
      );
    }
    return reels;
  }
}
