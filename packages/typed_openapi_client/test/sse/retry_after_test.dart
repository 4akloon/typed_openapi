import 'package:test/test.dart';
import 'package:typed_openapi_client/src/sse/retry_after.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);
  const responseDate = 'Sun, 06 Nov 1994 08:49:37 GMT';

  Duration? parse(String value, {String? responseDate}) =>
      RetryAfter.parse(value, responseDate: responseDate, now: now);

  test('delta-seconds', () {
    expect(parse('7'), const Duration(seconds: 7));
    expect(parse(' 7 '), const Duration(seconds: 7));
  });

  for (final value in ['0', '-5', 'abc', '', '1.5', '9' * 30, '+3']) {
    test('"$value" is unusable', () {
      expect(parse(value), isNull);
    });
  }

  test('nine digits are the longest delta', () {
    expect(parse('999999999'), const Duration(seconds: 999999999));
  });

  test('a date after the response date is the difference', () {
    expect(
      parse('Sun, 06 Nov 1994 08:49:47 GMT', responseDate: responseDate),
      const Duration(seconds: 10),
    );
  });

  test('a date before the response date is unusable', () {
    expect(
      parse('Sun, 06 Nov 1994 08:49:27 GMT', responseDate: responseDate),
      isNull,
    );
  });

  test('a date without a response date is measured against now', () {
    expect(
      parse('Wed, 21 Oct 2026 12:00:10 GMT'),
      const Duration(seconds: 10),
    );
  });

  test('an unparsable response date falls back to now', () {
    expect(
      parse('Wed, 21 Oct 2026 12:00:10 GMT', responseDate: 'garbage'),
      const Duration(seconds: 10),
    );
  });

  group('of', () {
    Duration? of(Failure<Object?, Object?> failure) =>
        RetryAfter.of(failure, clock: () => now);

    test('reads retry-after from an HttpError', () {
      expect(
        of(
          const HttpError(
            'x',
            statusCode: 503,
            headers: {
              'retry-after': ['7'],
            },
          ),
        ),
        const Duration(seconds: 7),
      );
    });

    test('reads retry-after from UndocumentedStatus and DecodeError', () {
      const headers = {
        'retry-after': ['3'],
      };
      expect(
        of(const UndocumentedStatus(statusCode: 503, headers: headers)),
        const Duration(seconds: 3),
      );
      expect(
        of(
          DecodeError(
            JsonDecodeException(expected: 'e', actual: 'a'),
            statusCode: 503,
            headers: headers,
          ),
        ),
        const Duration(seconds: 3),
      );
    });

    test('a date form uses the date header', () {
      expect(
        of(
          const HttpError(
            'x',
            statusCode: 503,
            headers: {
              'retry-after': ['Sun, 06 Nov 1994 08:49:47 GMT'],
              'date': [responseDate],
            },
          ),
        ),
        const Duration(seconds: 10),
      );
    });

    test('a date form without a date header uses the clock', () {
      expect(
        of(
          const HttpError(
            'x',
            statusCode: 503,
            headers: {
              'retry-after': ['Wed, 21 Oct 2026 12:00:10 GMT'],
            },
          ),
        ),
        const Duration(seconds: 10),
      );
    });

    test('no header gives null', () {
      expect(of(const HttpError('x', statusCode: 503)), isNull);
    });

    test('a transport error gives null', () {
      expect(
        of(
          const TransportError(
            TransportException(.connection, 'x'),
            StackTrace.empty,
          ),
        ),
        isNull,
      );
    });
  });
}
