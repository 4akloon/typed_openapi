import 'package:test/test.dart';
import 'package:typed_openapi_client/src/sse/http_date.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);
  final instant = DateTime.utc(1994, 11, 6, 8, 49, 37);

  test('the three forms of one instant parse equal', () {
    expect(HttpDate.parse('Sun, 06 Nov 1994 08:49:37 GMT', now: now), instant);
    expect(
      HttpDate.parse('Sunday, 06-Nov-94 08:49:37 GMT', now: now),
      instant,
    );
    expect(HttpDate.parse('Sun Nov  6 08:49:37 1994', now: now), instant);
  });

  test('an RFC 850 year within 50 years of now is in the future', () {
    expect(
      HttpDate.parse('Sunday, 06-Nov-70 08:49:37 GMT', now: now),
      DateTime.utc(2070, 11, 6, 8, 49, 37),
    );
  });

  test('an RFC 850 year more than 50 years ahead is the past one', () {
    expect(
      HttpDate.parse('Sunday, 06-Nov-80 08:49:37 GMT', now: now),
      DateTime.utc(1980, 11, 6, 8, 49, 37),
    );
  });

  test('a year nearest to now can be in the next century', () {
    expect(
      HttpDate.parse(
        'Sunday, 06-Nov-10 08:49:37 GMT',
        now: DateTime.utc(2090, 6, 1),
      ),
      DateTime.utc(2110, 11, 6, 8, 49, 37),
    );
  });

  test('exactly 50 years after now is still the future', () {
    expect(
      HttpDate.parse('Monday, 21-Oct-76 12:00:00 GMT', now: now),
      DateTime.utc(2076, 10, 21, 12),
    );
  });

  test('one second past 50 years after now is the past year', () {
    expect(
      HttpDate.parse('Monday, 21-Oct-76 12:00:01 GMT', now: now),
      DateTime.utc(1976, 10, 21, 12, 0, 1),
    );
  });

  for (final text in [
    '',
    'tomorrow',
    'Sun, 32 Nov 1994 08:49:37 GMT',
    'Sun, 31 Nov 1994 08:49:37 GMT',
    'Sun, 06 Nov 1994 25:00:00 GMT',
    'Sun, 06 Nov 1994 08:60:00 GMT',
    'Sun, 06 Foo 1994 08:49:37 GMT',
    'Sun, 06 Nov 1994 08:49:37 PST',
    'Sun, +6 Nov 1994 08:49:37 GMT',
  ]) {
    test('"$text" is not a date', () {
      expect(HttpDate.parse(text, now: now), isNull);
    });
  }
}
