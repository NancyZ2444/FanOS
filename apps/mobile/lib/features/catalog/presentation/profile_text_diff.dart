import 'package:flutter/material.dart';

/// Myers token diff. Chinese characters and whole Latin words are compared
/// independently. For completely rewritten long texts, labels remain sufficient:
/// avoid a giant colour block or unbounded quadratic work on the UI thread.
List<InlineSpan> profileDiffSpans(
  String before,
  String after, {
  required bool old,
}) {
  final tokens = RegExp(r'[A-Za-z0-9_]+|\s+|.', unicode: true);
  final a = tokens.allMatches(before).map((m) => m.group(0)!).toList();
  final b = tokens.allMatches(after).map((m) => m.group(0)!).toList();
  final sameA = List.filled(a.length, false),
      sameB = List.filled(b.length, false);
  final v = <int, int>{1: 0};
  final trace = <Map<int, int>>[];
  var found = false;
  for (var d = 0; d <= a.length + b.length && d <= 256; d++) {
    trace.add(Map.of(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && (v[k - 1] ?? 0) < (v[k + 1] ?? 0))
          ? v[k + 1] ?? 0
          : (v[k - 1] ?? 0) + 1;
      var y = x - k;
      while (x < a.length && y < b.length && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k] = x;
      if (x >= a.length && y >= b.length) {
        for (var step = trace.length - 1; step >= 0; step--) {
          final prior = trace[step], diagonal = x - y;
          final previous =
              diagonal == -step ||
                  (diagonal != step &&
                      (prior[diagonal - 1] ?? 0) < (prior[diagonal + 1] ?? 0))
              ? diagonal + 1
              : diagonal - 1;
          final px = prior[previous] ?? 0, py = px - previous;
          while (x > px && y > py) {
            sameA[--x] = true;
            sameB[--y] = true;
          }
          x = px;
          y = py;
        }
        found = true;
        break;
      }
    }
    if (found) break;
  }
  if (!found) return [TextSpan(text: old ? before : after)];
  final words = old ? a : b, same = old ? sameA : sameB;
  final spans = <InlineSpan>[];
  for (var i = 0; i < words.length;) {
    final unchanged = same[i];
    final buffer = StringBuffer();
    do {
      buffer.write(words[i++]);
    } while (i < words.length && same[i] == unchanged);
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: unchanged
            ? null
            : TextStyle(
                backgroundColor: old
                    ? const Color(0xFFF9EEEE)
                    : const Color(0xFFEDF6EF),
                color: old ? const Color(0xFF795B60) : const Color(0xFF336B4C),
              ),
      ),
    );
  }
  return spans;
}
