/// Turns names from a spec into Dart identifiers (R5).
///
/// A name is split into words at characters that are not ASCII letters or
/// digits and at case changes (`petId`, `HTTPServer`, `user_dto`); words
/// keep their case except the first letter, so `UserDTO` stays `UserDTO`.
/// Nothing is shortened or added by heuristics.
final class DartNames {
  /// Creates the converter.
  const DartNames();

  static final _separators = RegExp('[^A-Za-z0-9]+');
  static final _word = RegExp(
    '[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+',
  );

  /// Dart reserved words: never an identifier.
  static const reservedWords = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
    'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return',
    'super', 'switch', 'this', 'throw', 'true', 'try', 'var', 'void',
    'while', 'with',
    // Not reserved, but not usable inside async methods and generators.
    'await', 'yield',
  };

  /// Built-in identifiers: usable as members, not as type names.
  static const builtInIdentifiers = {
    'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export', //
    'extension', 'external', 'factory', 'Function', 'get', 'implements',
    'import', 'interface', 'late', 'library', 'mixin', 'operator', 'part',
    'required', 'set', 'static', 'typedef',
  };

  /// Type names a generated library sees without importing them: those of
  /// `dart:core`, `Uint8List` of `dart:typed_data`, and the names of
  /// `typed_openapi_runtime` that generated code uses.
  static const takenTypeNames = {
    // dart:core
    'ArgumentError', 'AssertionError', 'BigInt', 'BidirectionalIterator',
    'Comparable', 'Comparator', 'ConcurrentModificationError', 'DateTime',
    'Deprecated', 'Duration', 'Enum', 'Error', 'Exception', 'Expando',
    'Finalizer', 'FormatException', 'Function', 'Future', 'IndexError',
    'IntegerDivisionByZeroException', 'Invocation', 'Iterable', 'Iterator',
    'LateError', 'List', 'Map', 'MapEntry', 'Match', 'Never',
    'NoSuchMethodError', 'Null', 'Object', 'OutOfMemoryError', 'Pattern',
    'RangeError', 'Record', 'RegExp', 'RegExpMatch', 'Runes', 'Set', 'Sink',
    'StackOverflowError', 'StackTrace', 'StateError', 'Stopwatch', 'Stream',
    'String', 'StringBuffer', 'StringSink', 'Symbol', 'Type', 'TypeError',
    'UnimplementedError', 'UnsupportedError', 'Uri', 'WeakReference', 'bool',
    'double', 'int', 'num', 'Uint8List',
    // typed_openapi_runtime
    'CallOptions', 'Cancelled', 'CookieParameter', 'Date', 'DecodeError',
    'DioRequestSender', 'Failure', 'HeaderParameter', 'HttpError',
    'JsonDecodeException', 'JsonReader', 'JsonValue', 'OperationInfo',
    'OperationRequest', 'Patch', 'PatchNull', 'PatchValue', 'PathParameter',
    'QueryParameter', 'RawResponse', 'ResponseKind', 'Result', 'SseDecoder',
    'SseDecodeError', 'SseDisconnected', 'SseEvent', 'SseItem',
    'SseItemDecoder', 'SseMessage', 'Success', 'TransportError',
    'UndocumentedStatus',
  };

  /// Members every Dart object has, and the members generated models,
  /// enums and API classes add.
  static const objectMembers = {
    'hashCode', 'noSuchMethod', 'runtimeType', 'toString', //
  };

  /// Members a model's fields must not shadow.
  static const modelMembers = {
    ...objectMembers,
    'copyWith',
    'fromJson',
    'toJson',
  };

  /// Members an enum's values must not shadow.
  static const enumMembers = {
    ...objectMembers, 'fromJson', 'index', 'name', 'toJson', 'value', //
    'values',
  };

  /// Names of a method's arguments that generated code uses itself: the
  /// request body and the per-call options of the runtime.
  static const argumentNames = {'body', 'call'};

  /// The words of [text], in order; empty when it has no ASCII letter or
  /// digit.
  List<String> words(String text) => [
    for (final part in text.split(_separators))
      for (final match in _word.allMatches(part)) match[0]!,
  ];

  /// [text] as an UpperCamelCase type name, or null when it has no ASCII
  /// letter or digit. A name that starts with a digit gets a `$`.
  String? pascal(String text) {
    final parts = words(text);
    if (parts.isEmpty) return null;
    return _leading(parts.map(_capitalize).join());
  }

  /// [text] as a lowerCamelCase member name, or null when it has no ASCII
  /// letter or digit. A name that starts with a digit gets a `$`.
  String? camel(String text) {
    final parts = words(text);
    if (parts.isEmpty) return null;
    return _leading(
      [parts.first.toLowerCase(), ...parts.skip(1).map(_capitalize)].join(),
    );
  }

  static String _capitalize(String word) =>
      word[0].toUpperCase() + word.substring(1);

  static String _leading(String name) =>
      name.startsWith(RegExp('[0-9]')) ? '\$$name' : name;
}

/// Why [NameScope.claim] did not give the candidate itself.
enum NameChange {
  /// The candidate is a reserved word or a name Dart already has.
  reserved,

  /// Another declaration of the scope already has the candidate.
  collision,
}

/// The names of one scope (a library's types, a class's members, a
/// method's arguments), given out in the order they are claimed.
///
/// Callers claim in a deterministic order (by spec location), so the same
/// spec always gives the same names.
final class NameScope {
  /// Creates a scope where [reserved] names get [reservedSuffix].
  NameScope({required Set<String> reserved, required this.reservedSuffix})
    : _reserved = reserved;

  final Set<String> _reserved;
  final Set<String> _taken = {};

  /// What a reserved name gets appended: `Model` for types, `_` for
  /// members.
  final String reservedSuffix;

  /// Whether [name] is given out.
  bool isTaken(String name) => _taken.contains(name);

  /// Gives out [candidate], or a free name made from it: with
  /// [reservedSuffix] when it is reserved, then the first free of
  /// [alternatives], then with `2`, `3`, ... appended. Returns the name and
  /// why it differs from [candidate], if it does.
  (String, NameChange?) claim(
    String candidate, {
    List<String> alternatives = const [],
  }) {
    if (_reserved.contains(candidate)) {
      final name = _free('$candidate$reservedSuffix');
      return (name, .reserved);
    }
    if (_taken.add(candidate)) return (candidate, null);
    for (final alternative in alternatives) {
      if (!_reserved.contains(alternative) && _taken.add(alternative)) {
        return (alternative, .collision);
      }
    }
    return (_free(candidate), .collision);
  }

  String _free(String base) {
    if (_taken.add(base)) return base;
    for (var i = 2; ; i++) {
      if (_taken.add('$base$i')) return '$base$i';
    }
  }
}
