import '../model/schema.dart';
import 'schema_shapes.dart';

/// Tells whether a `default` fits the `enum` and the `format` of the schema
/// it is written for. A type that does not fit is the normalizer's (TOA211);
/// only the formats the client models are checked.
final class DefaultMatcher {
  /// Creates the matcher.
  const DefaultMatcher();

  static const _date = r'(\d{4})-(\d{2})-(\d{2})';
  static final _dateOnly = RegExp('^$_date\$');
  static final _dateTime = RegExp(
    '^$_date[Tt]'
    r'(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?'
    r'(?:[Zz]|[+-](\d{2}):(\d{2}))$',
  );
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static const _monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
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
    final match = _dateOnly.firstMatch(text);
    return match != null && _isCalendarDate(match);
  }

  /// An RFC 3339 `date-time`, checked by the range of each field:
  /// [DateTime.tryParse] rolls an out-of-range month or day over.
  static bool _isDateTime(String text) {
    final match = _dateTime.firstMatch(text);
    if (match == null || !_isCalendarDate(match)) return false;
    final hour = _number(match, 4);
    final minute = _number(match, 5);
    final second = _number(match, 6);
    // The second may be 60, a leap second.
    final isTime = hour <= 23 && minute <= 59 && second <= 60;
    // `Z` has no offset groups.
    return isTime && _number(match, 7) <= 23 && _number(match, 8) <= 59;
  }

  /// Whether the year, month and day in groups 1 to 3 of [match] are a day
  /// of the Gregorian calendar.
  static bool _isCalendarDate(RegExpMatch match) {
    final year = _number(match, 1);
    final month = _number(match, 2);
    final day = _number(match, 3);
    if (month < 1 || month > 12 || day < 1) return false;
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return day <= (month == 2 && isLeap ? 29 : _monthDays[month - 1]);
  }

  static int _number(RegExpMatch match, int group) =>
      int.parse(match[group] ?? '0');

  static bool _isInt32(num value) =>
      value == value.truncate() && value >= _int32Min && value <= _int32Max;
}
