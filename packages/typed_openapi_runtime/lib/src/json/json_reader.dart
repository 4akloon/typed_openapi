import 'dart:convert';
import 'dart:typed_data';

import '../model/date.dart';
import '../model/patch.dart';
import 'json_decode_exception.dart';
import 'json_objects.dart';
import 'json_value.dart';

/// Reads the properties of one JSON object for a generated `fromJson`.
///
/// Decoding is strict: a value of another JSON type is an error, and the
/// only widening is an integer where a `number` is expected. The first
/// mismatch stops decoding.
///
/// Every read takes a decoder, `T Function(Object? value)`: one of the
/// static decoders of this class ([asInt], [listOf], …), a generated
/// `fromJson`, or a user converter. A [JsonDecodeException] from the
/// decoder gets the property key prepended to its path, so a problem deep
/// inside the value names its full JSON pointer; a [FormatException] (as
/// `DateTime.parse` or a user converter throws) becomes a
/// [JsonDecodeException] at the property. Undeclared properties are
/// ignored.
///
/// ```dart
/// factory Pet.fromJson(Map<String, Object?> json) {
///   final r = JsonReader(json, schema: 'Pet');
///   return Pet(
///     id: r.required('id', JsonReader.asInt),
///     tags: r.optional(
///       'tags',
///       JsonReader.listOf(JsonReader.objectOf(Tag.fromJson)),
///     ),
///   );
/// }
/// ```
final class JsonReader {
  /// Reads [json], the value of [schema].
  const JsonReader(this.json, {required this.schema});

  /// Reads [value], which must be a JSON object.
  factory JsonReader.of(Object? value, {required String schema}) {
    try {
      return JsonReader(asObject(value), schema: schema);
    } on JsonDecodeException catch (e) {
      throw e.inSchema(schema);
    }
  }

  /// The deepest nesting of arrays and objects [checkDepth] accepts.
  static const int maxDepth = 1000;

  /// The object being read.
  final Map<String, Object?> json;

  /// The schema name reported in decoding errors.
  final String schema;

  /// A required, non-nullable property: absent and `null` are errors.
  T required<T extends Object>(String key, T Function(Object? value) decode) {
    _checkPresent(key);
    return _decode(key, _nonNull(key), decode);
  }

  /// A required, nullable property: absent is an error, `null` is `null`.
  T? requiredNullable<T extends Object>(
    String key,
    T Function(Object? value) decode,
  ) {
    _checkPresent(key);
    final value = json[key];
    return value == null ? null : _decode(key, value, decode);
  }

  /// An optional property, nullable or not: absent and `null` are both
  /// `null`, as the Dart field is `T?` either way (use [patch] to tell them
  /// apart).
  T? optional<T extends Object>(String key, T Function(Object? value) decode) {
    final value = json[key];
    return value == null ? null : _decode(key, value, decode);
  }

  /// A three-state property: absent gives `null`, `null` gives
  /// [Patch.nullValue], a value gives [Patch.value].
  Patch<T>? patch<T extends Object>(
    String key,
    T Function(Object? value) decode,
  ) {
    if (!json.containsKey(key)) return null;
    final value = json[key];
    return value == null
        ? const PatchNull()
        : PatchValue(_decode(key, value, decode));
  }

  /// A three-state property of any JSON value: absent gives `null`, `null`
  /// gives [Patch.nullValue], any other value [Patch.value].
  Patch<JsonValue>? patchValue(String key) {
    if (!json.containsKey(key)) return null;
    final value = json[key];
    return value == null ? const PatchNull() : PatchValue(JsonValue(value));
  }

  /// A required property of any JSON value (a schema without
  /// constraints); `null` is a value. Absent is an error.
  JsonValue requiredValue(String key) {
    _checkPresent(key);
    return JsonValue(json[key]);
  }

  /// An optional property of any JSON value; absent reads as
  /// `JsonValue(null)`. A [JsonValue] over `null` is `null` at run time, so
  /// `JsonValue?` could not tell absent from `null` anyway.
  JsonValue optionalValue(String key) => JsonValue(json[key]);

  /// A property that can hold one value only, a `const` or a one-value
  /// enum: anything but [value] is an error. Absent is an error when
  /// [required]; an optional property may also be `null`, which reads as
  /// absent.
  void constant(String key, Object value, {bool required = true}) {
    if (required) _checkPresent(key);
    final actual = json[key];
    if (actual == value || (!required && actual == null)) return;
    throw JsonDecodeException(
      expected: 'the constant ${jsonEncode(value)}',
      actual:
          JsonDecodeException.describe(actual) ==
              JsonDecodeException.describe(value)
          ? 'another value'
          : JsonDecodeException.describe(actual),
      path: [key],
      schema: schema,
    );
  }

  /// The properties whose keys are not in [known], read by [decode]: the
  /// `additionalProperties` of a model with properties, in JSON order. The
  /// map cannot be changed, as the model that holds it is immutable.
  Map<String, T> additional<T>(
    Set<String> known,
    T Function(Object? value) decode,
  ) => Map.unmodifiable({
    for (final MapEntry(:key, :value) in json.entries)
      if (!known.contains(key)) key: _decode(key, value, decode),
  });

  void _checkPresent(String key) {
    if (json.containsKey(key)) return;
    throw JsonDecodeException(
      expected: 'a required property',
      actual: 'no value',
      path: [key],
      schema: schema,
    );
  }

  Object _nonNull(String key) =>
      json[key] ??
      (throw JsonDecodeException(
        expected: 'a non-null value',
        actual: 'null',
        path: [key],
        schema: schema,
      ));

  T _decode<T>(String key, Object? value, T Function(Object? value) decode) =>
      _at(key, value, decode, schema: schema);

  /// Runs [decode] on [value] and moves its problem under [segment].
  static T _at<T>(
    Object segment,
    Object? value,
    T Function(Object? value) decode, {
    String? schema,
  }) {
    try {
      return decode(value);
    } on JsonDecodeException catch (e) {
      throw e.under(segment, schema: schema);
    } on FormatException catch (e) {
      throw JsonDecodeException.fromFormatException(
        e,
        path: [segment],
        schema: schema,
      );
    }
  }

  /// A JSON object.
  ///
  /// A map with `dynamic` keys is accepted when every key is a string; one
  /// with another key type is an error that names the key.
  static Map<String, Object?> asObject(Object? value) =>
      JsonObjects(value).require();

  /// A JSON array.
  static List<Object?> asList(Object? value) => switch (value) {
    final List<Object?> list => list,
    _ => throw _mismatch('an array', value),
  };

  /// A JSON string.
  static String asString(Object? value) => switch (value) {
    final String text => text,
    _ => throw _mismatch('a string', value),
  };

  /// A JSON boolean.
  static bool asBool(Object? value) => switch (value) {
    final bool flag => flag,
    _ => throw _mismatch('a boolean', value),
  };

  /// A JSON integer. A double is rejected, even `1.0`: `jsonDecode` gives
  /// an [int] for every integer literal small enough, so a double means the
  /// server wrote a fraction, an exponent or a number too big for `int`.
  static int asInt(Object? value) => switch (value) {
    final int number => number,
    _ => throw _mismatch('an integer', value),
  };

  /// A finite JSON number as a [double]; an integer is widened.
  static double asDouble(Object? value) => asNumber(value).toDouble();

  /// A finite JSON number. JSON has no infinity, but `jsonDecode('1e400')`
  /// gives one; it is rejected, because `jsonEncode` could not write it back.
  static num asNumber(Object? value) => switch (value) {
    final num number when number.isFinite => number,
    num() => throw JsonDecodeException(
      expected: 'a finite number',
      actual: 'a number out of the double range',
    ),
    _ => throw _mismatch('a number', value),
  };

  /// An RFC 3339 date-time string (`format: date-time`), such as
  /// `2024-02-03T04:05:06Z` or `2024-02-03T04:05:06.5+02:00`. A date-time
  /// without an offset is rejected (it does not name an instant), and so
  /// are dates that do not exist (`2024-02-30`) and leap seconds, which
  /// [DateTime] would silently roll over. The error carries
  /// [dateTimeHint]: the explicit fix when a server sends another format.
  static DateTime asDateTime(Object? value) {
    final text = asString(value);
    final match = _rfc3339.firstMatch(text);
    if (match != null) {
      final year = int.parse(match[1]!);
      final month = int.parse(match[2]!);
      final day = int.parse(match[3]!);
      if (day <= DateTime.utc(year, month + 1, 0).day) {
        return DateTime.parse(text.toUpperCase());
      }
    }
    throw JsonDecodeException(
      expected: 'an RFC 3339 date-time string',
      actual: _localDateTime.hasMatch(text)
          ? 'a date-time without an offset'
          : 'a string in another format',
      hint: dateTimeHint,
    );
  }

  /// The fix for a server that sends `date-time` in another format.
  static const String dateTimeHint =
      'If the server sends this format on purpose, map it to your own type '
      'with a converter (types.formats in the config, R6.8) or override the '
      "property's format";

  /// An RFC 3339 `full-date` string (`format: date`), such as `2024-02-03`.
  /// A date-time and a date that does not exist (`2024-02-30`) are rejected
  /// with [dateHint]; a date-time is reported as such, because the server
  /// sent one where a date was declared.
  static Date asDate(Object? value) {
    final text = asString(value);
    final date = Date.tryParse(text);
    if (date != null) {
      return date;
    }
    throw JsonDecodeException(
      expected: 'an RFC 3339 full-date string',
      actual: _rfc3339.hasMatch(text) || _localDateTime.hasMatch(text)
          ? 'a date-time'
          : 'a string in another format',
      hint: dateHint,
    );
  }

  /// The fix for a server that sends `date` in another format.
  static const String dateHint =
      'If the server sends this format on purpose, map it to your own type '
      'with a converter (types.formats in the config, R6.8) or override '
      "the property's format";

  /// Any JSON value.
  static JsonValue asValue(Object? value) => JsonValue(value);

  /// A base64 string (`format: byte`) as bytes. The URL-safe alphabet and
  /// missing padding are accepted, as RFC 4648 decoders commonly do.
  static Uint8List asBytes(Object? value) {
    final text = asString(value);
    try {
      return base64.decode(base64.normalize(text));
    } on FormatException {
      throw JsonDecodeException(
        expected: 'a base64 string',
        actual: 'a string in another format',
      );
    }
  }

  /// Runs [decode] and returns its value, or null when the JSON does not
  /// match: a [JsonDecodeException], or a [FormatException] of a decoder.
  /// A union without a discriminator tries its variants with it
  /// (`union: structural`).
  static T? attempt<T extends Object>(T Function() decode) {
    try {
      return decode();
    } on JsonDecodeException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// A decoder of a JSON object that a generated or user `fromJson` reads,
  /// such as `JsonReader.objectOf(Tag.fromJson)`.
  static T Function(Object? value) objectOf<T>(
    T Function(Map<String, Object?> json) fromJson,
  ) =>
      (value) => fromJson(asObject(value));

  /// A decoder that accepts `null` and otherwise uses [decode], for nullable
  /// array items and map values.
  static T? Function(Object? value) nullable<T extends Object>(
    T Function(Object? value) decode,
  ) =>
      (value) => value == null ? null : decode(value);

  /// A decoder of a JSON array whose items [decode] reads; a problem in an
  /// item gets the item index in its path.
  static List<T> Function(Object? value) listOf<T>(
    T Function(Object? value) decode,
  ) => (value) {
    final items = asList(value);
    return List<T>.generate(
      items.length,
      (index) => _at(index, items[index], decode),
      growable: false,
    );
  };

  /// A decoder of a JSON object with arbitrary keys (`additionalProperties`)
  /// whose values [decode] reads; keys keep the JSON order.
  static Map<String, T> Function(Object? value) mapOf<T>(
    T Function(Object? value) decode,
  ) => (value) {
    final entries = asObject(value);
    return <String, T>{
      for (final MapEntry(:key, value: item) in entries.entries)
        key: _at(key, item, decode),
    };
  };

  /// Checks that [json] nests arrays and objects at most [maxDepth] deep,
  /// without recursion; a deeper value would overflow the stack of a
  /// recursive `fromJson` or `jsonEncode`. The error path points at the
  /// first container that is too deep.
  static void checkDepth(Object? json) {
    if (json is! Map && json is! List) return;
    final levels = [_Level(json)];
    while (levels.isNotEmpty) {
      final level = levels.last;
      if (!level.moveNext()) {
        levels.removeLast();
        continue;
      }
      final child = level.value;
      if (child is! Map && child is! List) continue;
      if (levels.length >= maxDepth) {
        throw JsonDecodeException(
          expected: 'arrays and objects nested at most $maxDepth deep',
          actual: 'deeper nesting',
          path: [for (final l in levels) l.segment],
        );
      }
      levels.add(_Level(child));
    }
  }

  static final RegExp _rfc3339 = RegExp(
    r'^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])[Tt]'
    r'([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?'
    r'([Zz]|[+-]([01]\d|2[0-3]):[0-5]\d)$',
  );

  static final RegExp _localDateTime = RegExp(
    r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$',
  );

  static JsonDecodeException _mismatch(String expected, Object? value) =>
      JsonDecodeException(
        expected: expected,
        actual: JsonDecodeException.describe(value),
      );
}

/// One container on the explicit stack of [JsonReader.checkDepth].
final class _Level {
  _Level(Object? container)
    : _entries = switch (container) {
        final Map<Object?, Object?> map => map.entries.iterator,
        final List<Object?> list => list.asMap().entries.iterator,
        _ => const <MapEntry<Object?, Object?>>[].iterator,
      };

  final Iterator<MapEntry<Object?, Object?>> _entries;

  bool moveNext() => _entries.moveNext();

  Object get segment => _entries.current.key ?? 'null';

  Object? get value => _entries.current.value;
}
