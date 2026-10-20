export 'name_scope.dart';

/// What a Dart name is for: types are UpperCamelCase, members (fields,
/// methods, arguments) lowerCamelCase.
enum NameKind {
  /// A class, enum or extension type.
  type,

  /// A field, method or argument.
  member,
}

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
  static final _nonAsciiLetter = RegExp(
    r'(?![A-Za-z0-9])[\p{L}\p{M}\p{N}]',
    unicode: true,
  );
  static final _typeName = RegExp(r'^[A-Z$][A-Za-z0-9_$]*$');
  static final _memberName = RegExp(r'^[a-z$][A-Za-z0-9_$]*$');

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
  /// `dart:core`, `Uint8List` of `dart:typed_data`, the names of
  /// `typed_openapi_client` that generated code uses. Generated code imports
  /// nothing from an HTTP client, so `Dio`, `Response` or `Options` stay
  /// free for schemas.
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
    // typed_openapi_client
    'CallOptions', 'CancelSignal', 'Cancelled', 'ClientSender',
    'ClientTransport', 'CookieParameter', 'Date', 'DecodeError',
    'DeepEquality', 'Failure', 'FileUpload', 'FormBody', 'FormEncoding',
    'HeaderParameter', 'HttpError',
    'JsonDecodeException', 'JsonReader', 'JsonValue', 'MultipartBody',
    'MultipartPart', 'OperationInfo',
    'OperationRequest', 'Patch', 'PatchNull', 'PatchValue', 'PathParameter',
    'PathStyle', 'QueryParameter', 'QueryStyle', 'RawResponse',
    'ResponseKind', 'Result', 'SecurityLocation', 'SecurityScheme',
    'SecuritySchemeType', 'SecurityUse', 'SseCooldown', 'SseDecoder',
    'SseDecodeError',
    'SseDisconnected',
    'SseEvent',
    'SseEventIgnored',
    'SseItem',
    'SseItemDecoder', 'SseMessage', 'SseOptions', 'SseReconnecting',
    'SseReconnection', 'SseReconnector', 'SseResume', 'SseTrace',
    'SseTraceKind',
    'Success', 'TransportError', 'TransportException',
    'TransportExceptionKind', 'TransportRequest', 'TransportResponse',
    'UndocumentedStatus',
  };

  /// Members every Dart object has.
  static const objectMembers = {
    'hashCode', 'noSuchMethod', 'runtimeType', 'toString', //
  };

  /// The lowercase type names of `dart:core`: a member named like one
  /// would hide the type inside its class.
  static const lowercaseTypes = {'bool', 'double', 'int', 'num'};

  /// Members a model's fields must not shadow: the class's own members,
  /// the lowercase types and `base64Encode`, which its `toJson` calls.
  static const modelMembers = {
    ...objectMembers,
    ...lowercaseTypes,
    'base64Encode',
    'copyWith',
    'fromJson',
    'toJson',
  };

  /// Members an enum's values must not shadow, `unknown` among them: the
  /// emitters add an `unknown` member for a value the spec does not list
  /// (R8.1).
  static const enumMembers = {
    ...objectMembers, ...lowercaseTypes, 'fromJson', 'index', 'name', //
    'toJson', 'unknown', 'value', 'values',
  };

  /// The top-level functions of `dart:convert` that generated method bodies
  /// and parts classes call without a prefix: an argument or a field with
  /// the name would hide the function (`jsonEncode(jsonEncode)`).
  static const helperFunctions = {'base64Encode', 'jsonEncode'};

  /// Names a method of a group class must not have: the members of every
  /// object, the [helperFunctions] the other methods call without a prefix
  /// and the [lowercaseTypes] they use as types, which a method of the same
  /// name hides inside the class.
  static const methodNames = {
    ...objectMembers,
    ...helperFunctions,
    ...lowercaseTypes,
  };

  /// Names of a method's arguments that generated code uses itself: the
  /// request body and the per-call options of the runtime, and the
  /// [helperFunctions].
  static const argumentNames = {'body', 'call', ...helperFunctions};

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

  /// Whether [text] has a letter, digit or combining mark outside ASCII:
  /// [pascal] and [camel] drop it, so the name made from [text] is not the
  /// text any more. A change of case or of separators is not a loss.
  bool dropsLetters(String text) => _nonAsciiLetter.hasMatch(text);

  /// Whether [name] is a valid Dart name of [kind] as an override writes it:
  /// an identifier that starts with an uppercase letter (a type) or a
  /// lowercase letter (a member), or with `$`, and is not private (a
  /// leading `_` would make it invisible outside its library).
  bool isValid(String name, NameKind kind) =>
      (kind == .type ? _typeName : _memberName).hasMatch(name);

  /// The name of [kind] that [text] stands for: [pascal] or [camel]; null
  /// when [text] has no ASCII letter or digit.
  String? sanitize(String text, NameKind kind) =>
      kind == .type ? pascal(text) : camel(text);

  static String _capitalize(String word) =>
      word[0].toUpperCase() + word.substring(1);

  static String _leading(String name) =>
      name.startsWith(RegExp('[0-9]')) ? '\$$name' : name;
}
