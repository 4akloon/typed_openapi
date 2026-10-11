/// Finds text that nests too deeply to parse, without parsing it.
///
/// The YAML parser recurses once per nesting level and overflows the stack
/// at a few thousand levels. A `StackOverflowError` cannot be handled like
/// bad input, so loaders run this scan first and report such text as a
/// diagnostic instead.
///
/// The scan over-estimates and never under-estimates: inside `[...]` and
/// `{...}` it counts brackets outside quoted strings and comments; outside
/// them it counts the indentation of a line plus its leading `- ` markers.
final class NestingScanner {
  /// Creates a scanner.
  const NestingScanner();

  /// The deepest nesting a spec or config file may have.
  static const maxDepth = 1000;

  /// The offset in [text] where the nesting first exceeds [limit], or null
  /// when it never does.
  int? findTooDeep(String text, {int limit = maxDepth}) {
    var flow = 0;
    var block = 0;
    var flowBase = 0;
    var atLineStart = true;
    String? quote;
    var inComment = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') {
        inComment = false;
        if (quote == null && flow == 0) {
          atLineStart = true;
          block = 0;
        }
        continue;
      }
      if (inComment) continue;
      if (quote == '"') {
        if (char == r'\') {
          i++;
        } else if (char == '"') {
          quote = null;
        }
        continue;
      }
      if (quote == "'") {
        if (char == "'") {
          if (i + 1 < text.length && text[i + 1] == "'") {
            i++;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (atLineStart) {
        if (char == ' ' || char == '\t') {
          block++;
          if (block > limit) return i;
          continue;
        }
        if (char == '-' && _isBlank(text, i + 1)) {
          block += 2;
          if (block > limit) return i;
          i++;
          continue;
        }
        atLineStart = false;
      }
      switch (char) {
        case '#' when i == 0 || _isBlank(text, i - 1):
          inComment = true;
        case '"' || "'" when _startsToken(text, i):
          quote = char;
        case '[' || '{':
          if (flow == 0) flowBase = block;
          flow++;
          if (flowBase + flow > limit) return i;
        case ']' || '}':
          if (flow > 0) flow--;
      }
    }
    return null;
  }

  static bool _isBlank(String text, int i) =>
      i >= text.length || const {' ', '\t', '\n', '\r'}.contains(text[i]);

  static bool _startsToken(String text, int i) =>
      i == 0 ||
      const {' ', '\t', '\n', '\r', '[', '{', ',', ':', '-', '?'}.contains(
        text[i - 1],
      );
}
