import 'package:meta/meta.dart';

/// A calendar date without a time or time zone: the RFC 3339 `full-date`
/// (`YYYY-MM-DD`), which is the OpenAPI `format: date`.
///
/// ```dart
/// final birthday = Date(2024, 2, 29);
/// birthday.toJson(); // '2024-02-29'
/// Date.parse('2024-02-29') == birthday; // true
/// ```
@immutable
final class Date implements Comparable<Date> {
  /// Creates the date [year]-[month]-[day].
  ///
  /// Throws an [ArgumentError] when the year is outside 0..9999, the month
  /// is outside 1..12, or the day does not exist in that month, such as
  /// `Date(2023, 2, 29)`.
  Date(this.year, this.month, this.day) {
    RangeError.checkValueInInterval(year, 0, 9999, 'year');
    RangeError.checkValueInInterval(month, 1, 12, 'month');
    RangeError.checkValueInInterval(day, 1, _daysIn(year, month), 'day');
  }

  /// The calendar date of [dateTime] in its own time zone: its `year`,
  /// `month` and `day` fields, with no conversion to UTC.
  Date.fromDateTime(DateTime dateTime)
    : this(dateTime.year, dateTime.month, dateTime.day);

  /// Parses exactly `YYYY-MM-DD`: a four-digit year, a two-digit month and
  /// day, and a date that exists.
  ///
  /// Throws a [FormatException] otherwise: a time part, an offset,
  /// surrounding whitespace and other separators are all rejected.
  static Date parse(String text) =>
      tryParse(text) ??
      (throw FormatException('Not an RFC 3339 full-date (YYYY-MM-DD)', text));

  /// Like [parse], but returns `null` for invalid text.
  static Date? tryParse(String text) {
    final match = _fullDate.firstMatch(text);
    if (match == null) {
      return null;
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 || month > 12 || day < 1 || day > _daysIn(year, month)) {
      return null;
    }
    return Date(year, month, day);
  }

  /// The year, from 0 to 9999.
  final int year;

  /// The month, from 1 to 12.
  final int month;

  /// The day of the month, from 1 to 31.
  final int day;

  /// Midnight UTC of this date.
  DateTime toDateTimeUtc() => DateTime.utc(year, month, day);

  /// Whether this date is earlier than [other].
  bool isBefore(Date other) => compareTo(other) < 0;

  /// Whether this date is later than [other].
  bool isAfter(Date other) => compareTo(other) > 0;

  /// The JSON form, `YYYY-MM-DD`, zero-padded.
  String toJson() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Orders by year, then month, then day.
  @override
  int compareTo(Date other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) {
      return byYear;
    }
    final byMonth = month.compareTo(other.month);
    return byMonth != 0 ? byMonth : day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is Date &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// Same as [toJson].
  @override
  String toString() => toJson();

  static final RegExp _fullDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static int _daysIn(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;
}
