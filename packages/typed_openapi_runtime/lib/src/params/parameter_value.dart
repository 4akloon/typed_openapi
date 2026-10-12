import 'percent_encoder.dart';

/// A parameter value classified the way RFC 6570 expands it: undefined, a
/// scalar, a list or an object (name-value pairs).
///
/// The input is the JSON form of the value (`toJson` already applied):
/// `null`, [String], [num], [bool], a list of these or a string-keyed map of
/// these. `null` items and entries are skipped; an empty list or map is
/// undefined, like `null`. Anything else is a mistake of the calling code
/// and throws [ArgumentError].
sealed class ParameterValue {
  const ParameterValue();

  /// Classifies [value].
  factory ParameterValue.of(Object? value) => switch (value) {
    null => const UndefinedValue(),
    final List<Object?> list => _items(list),
    final Map<String, Object?> map => _pairs(map),
    _ => ScalarValue(text(value)),
  };

  /// Expands the value of the parameter [name] per RFC 6570:
  /// [first] starts a defined value, [separator] joins exploded items,
  /// [delimiter] joins items that are not exploded, [named] adds `name=`,
  /// [ifEmpty] follows the name of an empty scalar. Undefined gives `''`.
  String expand(
    String name, {
    required PercentEncoder encoder,
    required bool explode,
    required bool named,
    String first = '',
    String separator = ',',
    String delimiter = ',',
    String ifEmpty = '',
  });

  /// The text of a scalar JSON value.
  static String text(Object? value) => switch (value) {
    final String text => text,
    final bool flag => '$flag',
    final num number when number.isFinite => '$number',
    _ => throw ArgumentError.value(
      value,
      'value',
      'Not a finite JSON scalar; convert parameter values with toJson',
    ),
  };

  static ParameterValue _items(List<Object?> list) {
    final items = [
      for (final item in list)
        if (item != null) text(item),
    ];
    return items.isEmpty ? const UndefinedValue() : ListValue(items);
  }

  static ParameterValue _pairs(Map<String, Object?> map) {
    final pairs = [
      for (final MapEntry(:key, :value) in map.entries)
        if (value != null) (key, text(value)),
    ];
    return pairs.isEmpty ? const UndefinedValue() : ObjectValue(pairs);
  }
}

/// `null`, an empty list or an empty object: the parameter is not sent.
final class UndefinedValue extends ParameterValue {
  /// Creates an undefined value.
  const UndefinedValue();

  @override
  String expand(
    String name, {
    required PercentEncoder encoder,
    required bool explode,
    required bool named,
    String first = '',
    String separator = ',',
    String delimiter = ',',
    String ifEmpty = '',
  }) => '';
}

/// A string, number or boolean.
final class ScalarValue extends ParameterValue {
  /// Creates a scalar with its [text].
  const ScalarValue(this.text);

  /// The text of the value.
  final String text;

  @override
  String expand(
    String name, {
    required PercentEncoder encoder,
    required bool explode,
    required bool named,
    String first = '',
    String separator = ',',
    String delimiter = ',',
    String ifEmpty = '',
  }) {
    final value = encoder.encode(text);
    if (!named) return '$first$value';
    final key = PercentEncoder.unreserved.encode(name);
    return text.isEmpty ? '$first$key$ifEmpty' : '$first$key=$value';
  }
}

/// A list of scalars.
final class ListValue extends ParameterValue {
  /// Creates a list of item texts.
  const ListValue(this.items);

  /// The texts of the items.
  final List<String> items;

  @override
  String expand(
    String name, {
    required PercentEncoder encoder,
    required bool explode,
    required bool named,
    String first = '',
    String separator = ',',
    String delimiter = ',',
    String ifEmpty = '',
  }) {
    final key = PercentEncoder.unreserved.encode(name);
    final values = items.map(encoder.encode);
    if (explode) {
      final parts = named ? values.map((v) => '$key=$v') : values;
      return '$first${parts.join(separator)}';
    }
    final joined = values.join(delimiter);
    return named ? '$first$key=$joined' : '$first$joined';
  }
}

/// An object: name-value pairs in map order.
final class ObjectValue extends ParameterValue {
  /// Creates an object of property name and text pairs.
  const ObjectValue(this.pairs);

  /// The property names and the texts of their values.
  final List<(String, String)> pairs;

  @override
  String expand(
    String name, {
    required PercentEncoder encoder,
    required bool explode,
    required bool named,
    String first = '',
    String separator = ',',
    String delimiter = ',',
    String ifEmpty = '',
  }) {
    if (explode) {
      final parts = [
        for (final (key, value) in pairs)
          '${encoder.encode(key)}=${encoder.encode(value)}',
      ];
      return '$first${parts.join(separator)}';
    }
    final joined = [
      for (final (key, value) in pairs) ...[
        encoder.encode(key),
        encoder.encode(value),
      ],
    ].join(delimiter);
    if (!named) return '$first$joined';
    return '$first${PercentEncoder.unreserved.encode(name)}=$joined';
  }
}
