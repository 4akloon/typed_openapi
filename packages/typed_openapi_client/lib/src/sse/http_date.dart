/// Parses the three HTTP date forms RFC 9110 requires a recipient to
/// accept.
///
/// `dart:io` has an `HttpDate`, but the client also runs on the web.
// ignore: avoid_classes_with_only_static_members, a namespace the plan names (SseRetry.isTransient) so a user override can call it.
abstract final class HttpDate {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _maxLength = 64;
  static final _whitespace = RegExp(r'\s+');

  /// The instant [text] names, in UTC, or null when it is none of IMF-fixdate
  /// (`Sun, 06 Nov 1994 08:49:37 GMT`), RFC 850 (`Sunday, 06-Nov-94
  /// 08:49:37 GMT`) or asctime (`Sun Nov  6 08:49:37 1994`), or a field is
  /// out of range.
  ///
  /// A two-digit RFC 850 year more than 50 years after [now] is the most
  /// recent past year with those digits.
  static DateTime? parse(String text, {required DateTime now}) {
    if (text.length > _maxLength) return null;
    final parts = text.trim().split(_whitespace);
    return switch (parts) {
      [final day, final date, final month, final year, final time, 'GMT']
          when day.endsWith(',') =>
        _build(year, month, date, time, now: now),
      [final day, final dated, final time, 'GMT'] when day.endsWith(',') =>
        _fromRfc850(dated, time, now),
      [_, final month, final date, final time, final year] => _build(
        year,
        month,
        date,
        time,
        now: now,
      ),
      _ => null,
    };
  }

  static DateTime? _fromRfc850(String dated, String time, DateTime now) {
    final fields = dated.split('-');
    if (fields.length != 3 || fields[2].length != 2) return null;
    return _build(fields[2], fields[1], fields[0], time, now: now);
  }

  static DateTime? _build(
    String year,
    String month,
    String day,
    String time, {
    required DateTime now,
  }) {
    final clock = time.split(':');
    final monthIndex = _months.indexOf(month);
    final fields = [year, day, ...clock].map(_digits).toList();
    if (monthIndex < 0 || clock.length != 3 || fields.contains(null)) {
      return null;
    }
    final [y, d, hour, minute, second] = fields.cast<int>();
    final fullYear = year.length == 2
        ? _expandYear(y, monthIndex + 1, d, now)
        : y;
    final result = DateTime.utc(
      fullYear,
      monthIndex + 1,
      d,
      hour,
      minute,
      second,
    );
    final isExact =
        result.year == fullYear &&
        result.month == monthIndex + 1 &&
        result.day == d &&
        hour < 24 &&
        minute < 60 &&
        second < 60;
    return isExact ? result : null;
  }

  static int _expandYear(int twoDigits, int month, int day, DateTime now) {
    final century = now.year - now.year % 100;
    final candidate = century + twoDigits;
    final limit = DateTime.utc(now.year + 50, now.month, now.day, 23, 59, 59);
    final isTooFar = DateTime.utc(candidate, month, day).isAfter(limit);
    return isTooFar ? candidate - 100 : candidate;
  }

  static int? _digits(String text) =>
      text.isNotEmpty && text.length <= 4 && text.codeUnits.every(_isDigit)
      ? int.parse(text)
      : null;

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
}
