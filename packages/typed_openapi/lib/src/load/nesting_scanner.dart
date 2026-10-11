/// Finds text that the YAML parser cannot be trusted with, without parsing
/// it: text that nests too deeply, aliases in positions this tool does not
/// support, and explicit `?` keys in a document that uses aliases.
///
/// The YAML parser recurses once per nesting level and overflows the stack
/// at a few thousand levels. A `StackOverflowError` cannot be handled like
/// bad input, so loaders run this scan first and report such text as a
/// diagnostic instead.
///
/// An alias in a mapping key, or inside a collection used as a key, makes
/// the parser compare and hash the aliased value as a tree, which takes
/// exponential time for an alias bomb and happens before any later check
/// can see it. Rather than recognise every such key, the scan accepts an
/// alias only as a block value: after `key: ` or `- ` outside flow
/// collections, with nothing but blanks and a comment after it on its line
/// (`<<: *a` included). Any other alias (in `[...]` or `{...}`, in key
/// position, followed by more text, alone on a line) is a finding. An alias
/// token is a `*` at a value start; `*` in plain or quoted scalars, block
/// scalars and comments does not count. In a document that has an alias, an
/// explicit `?` key is a finding too, because its content can hold block
/// aliases (`?\n- *a`); without aliases `?` keys are left alone.
///
/// The scan follows just enough YAML context to find the syntax: `[`, `{`,
/// `'` and `"` mean something only where a value starts (the first thing on
/// a line, after `- `, after a mapping key's `: `, and inside a flow
/// collection after `[`, `{`, `,` or `:`, or as the first thing on a line,
/// where package:yaml starts a new token). A `#` there is a comment too,
/// as package:yaml reads it. Anywhere else they are plain
/// scalar content and are ignored, as are block scalars (`|`, `>`), quoted
/// strings and comments. A line that continues a multi-line plain scalar
/// (the previous line ended in plain text and this one is indented deeper
/// than its parent) is plain text from its first character.
///
/// The block markers `- `, `? ` and `: ` (the value indicator of an empty
/// key) each nest one level, so `: : : x` counts like `- - - x`.
///
/// The depth is the larger of two counts. Outside flow collections it is
/// the indentation of a line plus its leading `- ` markers. Inside
/// `[...]` and `{...}` it is the bracket count on top of the indentation
/// of the line that opened them, and a `- ` marker at the start of a line
/// there still adds its own depth, but plain indentation does not, so
/// pretty-printed JSON is not counted twice.
///
/// The scan counts nested brackets and block markers. It does not count the
/// implicit single-pair mapping of `[k: v]`, so for such text it can
/// under-estimate by up to a factor of two (the parser handles 2000 levels
/// of it), and the converter's own depth check applies afterwards. It can
/// over-estimate on contrived input, such as a flow collection written where
/// the parser would read a plain scalar.
final class NestingScanner {
  /// Creates a scanner.
  const NestingScanner();

  /// The deepest nesting a spec or config file may have.
  static const maxDepth = 1000;

  /// The offset in [text] where the nesting first exceeds [limit], or null
  /// when it never does.
  int? findTooDeep(String text, {int limit = maxDepth}) =>
      scan(text, limit: limit, aliases: false)?.offset;

  /// The offset in [text] of the first alias in an unsupported position or
  /// the first explicit `?` key of a document with aliases, or null.
  int? findUnsupportedAlias(String text) =>
      scan(text, limit: _unlimited)?.offset;

  static const _unlimited = 1 << 60;

  /// Scans [text] once and returns the first [ScanFinding], or null.
  ///
  /// With [aliases] false aliases and `?` keys are not looked for.
  ScanFinding? scan(
    String text, {
    int limit = maxDepth,
    bool aliases = true,
  }) {
    var indicatorValue = false;
    var lineHasContent = false;
    var valuePending = false;
    var parentColumn = -1;
    var sawAlias = false;
    int? complexKey;
    var contentSeen = false;
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
          if (flow == 0 && lineHasContent) valuePending = valueStart;
          lineHasContent = false;
          indicatorValue = false;
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
            if (block > limit) return ScanFinding._(.tooDeep, i);
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
            if (char == '?') complexKey ??= i;
            plainOpen = false;
            lineHasContent = true;
            indicatorValue = char == '-' && marker == 1;
            if (flow == 0) {
              markerColumn = block;
              parentColumn = block;
              block += marker;
              if (block > limit) return ScanFinding._(.tooDeep, i);
            } else {
              lineMarkers += marker == 1 ? 2 : marker;
              if (lineMarkers > limit) return ScanFinding._(.tooDeep, i);
            }
            i += marker - 1;
            continue;
          }
          atLineStart = false;
          wasLineStart = true;
        }
      }
      if (char == ' ' || char == '\t') continue;
      final atValue = valueStart || (flow > 0 && wasLineStart);
      final afterIndicator = indicatorValue;
      valueStart = false;
      indicatorValue = false;
      if (char == '#' &&
          (i == 0 || _isBlank(text, i - 1) || (flow > 0 && atValue))) {
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
      lineHasContent = true;
      final rootLevel = !contentSeen;
      contentSeen = true;
      if (atValue && char == '*') {
        sawAlias = true;
        final end = _propertyEnd(text, i);
        if (flow > 0 || !afterIndicator || !_endsLine(text, end)) {
          if (aliases) return ScanFinding._(.alias, i);
        }
        plainOpen = false;
        i = end - 1;
        continue;
      }
      if (flow > 0 && atValue && char == '?') {
        if (_isBlank(text, i + 1)) complexKey ??= i;
        valueStart = true;
        continue;
      }
      if (atValue && (char == '"' || char == "'")) {
        plainOpen = false;
        quote = char;
        continue;
      }
      if (atValue && (char == '[' || char == '{')) {
        if (flow == 0) flowBase = rootLevel && block == 0 ? -1 : block;
        plainOpen = false;
        flow++;
        if (flowBase + flow > limit) return ScanFinding._(.tooDeep, i);
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
          : valuePending
          ? parentColumn
          : block - 1;
      if (atValue && (char == '|' || char == '>')) {
        plainOpen = false;
        i = _blockScalarEnd(text, i, threshold) - 1;
        atLineStart = true;
        valueStart = true;
        valuePending = false;
        lineHasContent = false;
        block = 0;
        markerColumn = -1;
        continue;
      }
      if (char == ':' && _isBlank(text, i + 1)) {
        plainOpen = false;
        valueStart = true;
        indicatorValue = true;
        parentColumn = block;
      } else {
        if (atValue) {
          plainOpen = true;
          plainThreshold = threshold;
        }
      }
    }
    return aliases && sawAlias ? _finding(complexKey) : null;
  }

  static ScanFinding? _finding(int? complexKey) =>
      complexKey == null ? null : ScanFinding._(.alias, complexKey);

  /// Whether only blanks and a comment follow [from] on its line.
  static bool _endsLine(String text, int from) {
    var i = from;
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    return i >= text.length ||
        _isBreak(text[i]) ||
        (text[i] == '#' && i > from);
  }

  /// The length of the block marker (`- `, `? `, `: ` or `---`) at [i], or 0.
  static int _markerLength(String text, int i) {
    final char = text[i];
    if ((char == '-' || char == '?' || char == ':') && _isBlank(text, i + 1)) {
      return 1;
    }
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

/// What [NestingScanner.scan] found.
final class ScanFinding {
  const ScanFinding._(this.problem, this.offset);

  /// The kind of problem.
  final ScanProblem problem;

  /// The offset in the scanned text where the problem starts.
  final int offset;
}

/// A kind of problem [NestingScanner] reports.
enum ScanProblem {
  /// The text nests deeper than the limit.
  tooDeep,

  /// An alias is in an unsupported position, or a document with aliases has
  /// an explicit `?` key.
  alias,
}
