/// Suggests the known key a mistyped key most likely stands for.
final class KeySuggestion {
  KeySuggestion._();

  /// How many edits a key may be away from a known key to be suggested.
  static const _maxTypoDistance = 2;

  /// The first of the sorted [known] keys at the smallest edit distance
  /// from [key], when that distance is at most [_maxTypoDistance].
  static String? closest(String key, List<String> known) {
    String? best;
    var bestDistance = _maxTypoDistance + 1;
    for (final candidate in known) {
      final distance = _distance(key, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The Levenshtein distance between [a] and [b].
  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + substitution,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
