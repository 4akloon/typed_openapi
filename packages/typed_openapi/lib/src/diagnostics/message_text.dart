/// Makes text taken from a spec safe to print in a message or a report line.
///
/// A spec string (an event name, a property) may hold an escape sequence
/// that moves a terminal's cursor, a line break that starts a line such as
/// `::error::...` (a GitHub workflow command), or a bidirectional mark that
/// reorders the text around it.
final class MessageText {
  const MessageText._();

  /// [text] in double quotes, with `"`, `\`, controls and bidirectional
  /// marks written as escapes: safe to put in the middle of a message.
  static String quote(String text) {
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"${neutralise(escaped)}"';
  }

  /// [text] with every control character, line separator and
  /// bidirectional mark written as an escape (`\n`, `\u{1b}`); a line feed
  /// stays one when [keepLineFeeds] is true.
  static String neutralise(String text, {bool keepLineFeeds = false}) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A && keepLineFeeds) {
        out.writeCharCode(rune);
      } else if (_isHidden(rune)) {
        out.write(_escape(rune));
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static String _escape(int rune) => switch (rune) {
    0x0A => r'\n',
    0x0D => r'\r',
    0x09 => r'\t',
    _ => '\\u{${rune.toRadixString(16)}}',
  };

  /// Whether [rune] is not printed as itself: a C0 or C1 control, DEL, a
  /// line or paragraph separator, or a bidirectional control.
  static bool _isHidden(int rune) =>
      rune < 0x20 ||
      (rune >= 0x7F && rune <= 0x9F) ||
      rune == 0x061C ||
      rune == 0x200E ||
      rune == 0x200F ||
      (rune >= 0x2028 && rune <= 0x202E) ||
      (rune >= 0x2066 && rune <= 0x2069);
}
