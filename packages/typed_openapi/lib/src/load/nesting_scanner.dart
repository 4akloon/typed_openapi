/// Finds text that nests too deeply to parse, without parsing it.
///
/// The YAML parser recurses once per nesting level and overflows the stack
/// at a few thousand levels. A `StackOverflowError` cannot be handled like
/// bad input, so loaders run this scan first and report such text as a
/// diagnostic instead.
///
/// The scan follows just enough YAML context to find the syntax: `[`, `{`,
/// `'` and `"` mean something only where a value starts (the first thing on
/// a line, after `- `, after a mapping key's `: `, and inside a flow
/// collection after `[`, `{`, `,` or `:`). Anywhere else they are plain
/// scalar content and are ignored, as are block scalars (`|`, `>`), quoted
/// strings and comments. A line that continues a multi-line plain scalar
/// (the previous line ended in plain text and this one is indented deeper
/// than its parent) is plain text from its first character.
///
/// The depth is the larger of two counts. Outside flow collections it is
/// the indentation of a line plus its leading `- ` markers. Inside
/// `[...]` and `{...}` it is the bracket count on top of the indentation
/// of the line that opened them, and a `- ` marker at the start of a line
/// there still adds its own depth, but plain indentation does not, so
/// pretty-printed JSON is not counted twice.
///
/// For text that the YAML parser reads as nested collections the scan does
/// not under-estimate. It can over-estimate on contrived input, such as a
/// flow collection written where the parser would read a plain scalar.
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
    var markerColumn = -1;
    var lineMarkers = 0;
    var plainOpen = false;
    var plainThreshold = -1;
    var atLineStart = true;
    var valueStart = true;
    String? quote;
    var inComment = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        inComment = false;
        if (quote == null) {
          atLineStart = true;
          lineMarkers = 0;
          if (flow == 0) {
            valueStart = true;
            block = 0;
            markerColumn = -1;
          }
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
      var wasLineStart = false;
      if (atLineStart) {
        if (char == ' ' || char == '\t') {
          if (flow == 0) {
            block++;
            if (block > limit) return i;
          }
          continue;
        }
        if (flow == 0 &&
            plainOpen &&
            markerColumn < 0 &&
            char != '#' &&
            block > plainThreshold) {
          // Continues a plain scalar: text, not syntax.
          atLineStart = false;
          valueStart = false;
        } else {
          final marker = _markerLength(text, i);
          if (marker > 0) {
            if (flow == 0) {
              markerColumn = block;
              block += marker;
              if (block > limit) return i;
            } else {
              lineMarkers += marker == 1 ? 2 : marker;
              if (lineMarkers > limit) return i;
            }
            i += marker - 1;
            continue;
          }
          atLineStart = false;
          wasLineStart = true;
        }
      }
      if (char == ' ' || char == '\t') continue;
      final atValue = valueStart;
      valueStart = false;
      if (char == '#' && (i == 0 || _isBlank(text, i - 1))) {
        inComment = true;
        plainOpen = false;
        valueStart = atValue;
        continue;
      }
      if (atValue && (char == '&' || char == '!')) {
        plainOpen = false;
        i = _propertyEnd(text, i) - 1;
        valueStart = true;
        continue;
      }
      if (atValue && (char == '"' || char == "'")) {
        plainOpen = false;
        quote = char;
        continue;
      }
      if (atValue && (char == '[' || char == '{')) {
        if (flow == 0) flowBase = block;
        plainOpen = false;
        flow++;
        if (flowBase + flow > limit) return i;
        valueStart = true;
        continue;
      }
      if (flow > 0) {
        plainOpen = false;
        if (char == ']' || char == '}') {
          flow--;
        } else if (char == ',' || char == ':') {
          valueStart = true;
        }
        continue;
      }
      final threshold = !wasLineStart
          ? block
          : markerColumn >= 0
          ? markerColumn
          : block - 1;
      if (atValue && (char == '|' || char == '>')) {
        plainOpen = false;
        i = _blockScalarEnd(text, i, threshold) - 1;
        atLineStart = true;
        valueStart = true;
        block = 0;
        markerColumn = -1;
        continue;
      }
      if (char == ':' && _isBlank(text, i + 1)) {
        plainOpen = false;
        valueStart = true;
      } else {
        plainOpen = true;
        if (atValue) plainThreshold = threshold;
      }
    }
    return null;
  }

  /// The length of the block marker (`- `, `? ` or `---`) at [i], or 0.
  static int _markerLength(String text, int i) {
    final char = text[i];
    if ((char == '-' || char == '?') && _isBlank(text, i + 1)) return 1;
    if (char == '-' && text.startsWith('---', i) && _isBlank(text, i + 3)) {
      return 3;
    }
    return 0;
  }

  /// The end of the anchor or tag that starts at [start].
  static int _propertyEnd(String text, int start) {
    var end = start + 1;
    while (end < text.length &&
        !_isBlank(text, end) &&
        !const {',', '[', ']', '{', '}'}.contains(text[end])) {
      end++;
    }
    return end;
  }

  /// The offset where normal scanning resumes after the block scalar whose
  /// indicator is at [indicator]: the start of the first line that is not
  /// blank and is not indented deeper than [threshold].
  static int _blockScalarEnd(String text, int indicator, int threshold) {
    var position = _afterBreak(text, _lineEnd(text, indicator));
    while (position < text.length) {
      var indent = 0;
      while (position + indent < text.length &&
          text[position + indent] == ' ') {
        indent++;
      }
      var content = position + indent;
      while (content < text.length &&
          (text[content] == ' ' || text[content] == '\t')) {
        content++;
      }
      final blank = content >= text.length || _isBreak(text[content]);
      if (!blank && indent <= threshold) return position;
      position = _afterBreak(text, _lineEnd(text, content));
    }
    return text.length;
  }

  static bool _isBreak(String char) => char == '\n' || char == '\r';

  static int _lineEnd(String text, int from) {
    var end = from;
    while (end < text.length && !_isBreak(text[end])) {
      end++;
    }
    return end;
  }

  static int _afterBreak(String text, int lineEnd) {
    if (lineEnd >= text.length) return text.length;
    if (text[lineEnd] == '\r' &&
        lineEnd + 1 < text.length &&
        text[lineEnd + 1] == '\n') {
      return lineEnd + 2;
    }
    return lineEnd + 1;
  }

  static bool _isBlank(String text, int i) =>
      i >= text.length || const {' ', '\t', '\n', '\r'}.contains(text[i]);
}
