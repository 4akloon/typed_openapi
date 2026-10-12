import '../model/schema.dart';
import 'schema_shapes.dart';

/// Tells whether a `default` fits the `enum` and the `format` of the schema
/// it is written for. A type that does not fit is the normalizer's (TOA211);
/// only the formats the client models are checked.
final class DefaultMatcher {
  /// Creates the matcher.
  const DefaultMatcher();

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _dateTime = RegExp(
    r'^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})$',
  );
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static const _int32Min = -2147483648;
  static const _int32Max = 2147483647;

  /// Why [value] does not fit one of [sources], the schemas the parameter's
  /// schema stands for; null when it fits all of them (also a `null` value,
  /// which no enum or format judges).
  String? mismatch(Object? value, Iterable<SchemaObject> sources) {
    if (value == null) return null;
    for (final source in sources) {
      final values = SchemaShapes.enumValues(source);
      if (values != null && !values.contains(value)) {
        return 'is not one of the values of the enum ($values)';
      }
      if (source.format case final format?) {
        if (!_fits(value, format)) return 'is not a valid "$format" value';
      }
    }
    return null;
  }

  static bool _fits(Object value, String format) => switch (format) {
    'date' => value is String && _isDate(value),
    'date-time' => value is String && _isDateTime(value),
    'uuid' => value is String && _uuid.hasMatch(value),
    'int32' => value is! num || _isInt32(value),
    _ => true,
  };

  static bool _isDate(String text) {
    if (!_date.hasMatch(text)) return false;
    final parsed = DateTime.tryParse(text);
    return parsed != null && parsed.toIso8601String().startsWith(text);
  }

  static bool _isDateTime(String text) =>
      _dateTime.hasMatch(text) && DateTime.tryParse(text) != null;

  static bool _isInt32(num value) =>
      value == value.truncate() && value >= _int32Min && value <= _int32Max;
}
