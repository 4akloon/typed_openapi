/// The hostile strings the fuzz puts at every sink a spec string reaches
/// (spec decision 5).
abstract final class Hostile {
  /// Strings for sinks that become literals or names: property keys, enum
  /// values, parameter and event names, discriminator values. Quotes, `$`,
  /// backslashes, comment and doc-comment markers, line breaks, a bidi
  /// control, reserved words and names the runtime or the emitter use.
  static const List<String> names = [
    "it's",
    r'$cost',
    r'back\slash',
    '*/ name',
    '{@macro x}',
    'line\nbreak',
    'line\r\nfeed',
    '\u202Eevil',
    'para\u2029graph',
    'class',
    'toString',
    'hashCode',
    'unknown',
    '',
    'Delta',
    'delta',
    '"double"',
    'tab\there',
  ];

  /// Strings for sinks that become documentation: descriptions, titles and
  /// summaries; each tries to leave its comment.
  static const List<String> texts = [
    '*/ injected();',
    '\ninjected();',
    '\r\ninjected();',
    'a [link] and <b>tag</b> {@macro y}',
    '```\ncode\n```',
    '\u2028injected();',
    r'ends with a backslash \',
    r"$it's",
  ];

  /// Media types that are valid by RFC 9110 and hold characters that a
  /// Dart string literal must escape.
  static const List<String> mediaTypes = [
    r"application/x-it's$cost+json",
    'application/vnd.a+json',
  ];
}
