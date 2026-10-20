import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/watch_opening.dart';

void main() {
  const s1 = Duration(seconds: 1);
  const s2 = Duration(seconds: 2);
  const ok = WatchOpening.stream;
  const status = WatchOpening.status;

  late WatchOpening watch;
  setUp(() => watch = WatchOpening());

  /// A transport that answers with the [answers] in order.
  FakeTransport script(List<Object> answers) {
    var i = 0;
    return FakeTransport((_) {
      final answer = answers[i < answers.length ? i : answers.length - 1];
      i++;
      if (answer is TransportException) throw answer;
      return answer as TransportResponse;
    });
  }

  const retry = SseOptions(reconnect: true);

  Future<Result<Stream<SseItem<String>>, String>> open(
    FakeTransport transport, {
    SseOptions sse = retry,
  }) => watch.open(transport, sse: sse);

  Future<Result<Stream<SseItem<String>>, String>> retryAfter(
    String value, {
    String? date,
  }) => open(
    script([
      status(
        503,
        headers: {'retry-after': value, 'date': ?date},
      ),
      ok('data: a\n\n'),
    ]),
  );

  test('a 503 then a 200 opens after one retry', () async {
    final transport = script([status(503), ok('data: a\n\n')]);
    final result = await open(transport);
    final items = await (result as Success<Stream<SseItem<String>>, String>)
        .data
        .take(1)
        .toList();
    expect(transport.requests, hasLength(2));
    expect(watch.waits, [s1]);
    expect((items.first as SseEvent<String>).data, 'a');
  });

  test('a connection error then a 200 opens', () async {
    final transport = script([
      const TransportException(.connection, 'x'),
      ok('data: a\n\n'),
    ]);
    expect(await open(transport), isA<Success<Object?, Object?>>());
    expect(transport.requests, hasLength(2));
  });

  for (final code in [404, 401]) {
    test('a $code is returned with zero retries', () async {
      final transport = script([status(code)]);
      final result = await open(transport);
      expect(
        result,
        isA<UndocumentedStatus<Object?, Object?>>().having(
          (f) => f.statusCode,
          'statusCode',
          code,
        ),
      );
      expect(transport.requests, hasLength(1));
      expect(watch.waits, isEmpty);
    });
  }

  test('a 429 with Retry-After: 7 waits 7 s when the backoff is 1 s', () async {
    await retryAfter('7');
    expect(watch.waits, [const Duration(seconds: 7)]);
  });

  test('the longer of Retry-After and the backoff', () async {
    final transport = script([
      status(503),
      status(503, headers: {'Retry-After': '1'}),
      ok('data: a\n\n'),
    ]);
    await open(transport);
    expect(watch.waits, [s1, s2]);
  });

  test('Retry-After as an HTTP-date 10 s after the response Date', () async {
    await retryAfter(
      'Sun, 06 Nov 1994 08:49:47 GMT',
      date: 'Sun, 06 Nov 1994 08:49:37 GMT',
    );
    expect(watch.waits, [const Duration(seconds: 10)]);
  });

  test('a past date falls back to the backoff', () async {
    await retryAfter(
      'Sun, 06 Nov 1994 08:49:27 GMT',
      date: 'Sun, 06 Nov 1994 08:49:37 GMT',
    );
    expect(watch.waits, [s1]);
  });

  for (final garbage in [
    'abc',
    '-5',
    '9' * 30,
    'Sun, 06 Nov 1994 25:00:00 GMT',
  ]) {
    test('Retry-After "$garbage" falls back to the backoff', () async {
      await retryAfter(garbage, date: 'Sun, 06 Nov 1994 08:49:37 GMT');
      expect(watch.waits, [s1]);
    });
  }

  test('a Retry-After above maxDelay is not capped', () async {
    await retryAfter('120');
    expect(watch.waits, [const Duration(seconds: 120)]);
  });

  test('a DecodeError with status 503 is transient', () async {
    final html = WatchOpening.status(
      503,
      headers: {'content-type': 'application/json'},
      body: '<html>',
    );
    final transport = script([html, ok('data: a\n\n')]);
    expect(await open(transport), isA<Success<Object?, Object?>>());
    expect(transport.requests, hasLength(2));
  });

  test('a 501 is final', () async {
    final transport = script([status(501)]);
    await open(transport);
    expect(transport.requests, hasLength(1));
  });

  test('a TransportError of kind other is final', () async {
    final transport = script([const TransportException(.other, 'x')]);
    expect(await open(transport), isA<TransportError<Object?, Object?>>());
    expect(transport.requests, hasLength(1));
  });

  test('maxAttempts used up returns the last failure', () async {
    final transport = script([status(503), status(502), status(504)]);
    final result = await open(
      transport,
      sse: const SseOptions(reconnect: true, maxAttempts: 2),
    );
    expect(
      result,
      isA<UndocumentedStatus<Object?, Object?>>().having(
        (f) => f.statusCode,
        'statusCode',
        504,
      ),
    );
    expect(transport.requests, hasLength(3));
    expect(watch.waits, [s1, s2]);
  });

  test('maxAttempts: 0 behaves as 0.2.0', () async {
    final transport = script([status(503)]);
    final result = await open(
      transport,
      sse: const SseOptions(reconnect: true, maxAttempts: 0),
    );
    expect(result, isA<UndocumentedStatus<Object?, Object?>>());
    expect(transport.requests, hasLength(1));
  });

  test('the cooldown applies at the opening', () async {
    final transport = script([
      status(503),
      status(503),
      status(503),
      ok('data: a\n\n'),
    ]);
    await open(
      transport,
      sse: const SseOptions(
        reconnect: true,
        maxAttempts: null,
        cooldown: SseCooldown(after: 2, duration: Duration(minutes: 5)),
      ),
    );
    expect(watch.waits, [s1, s2, const Duration(minutes: 5)]);
  });

  test(
    'a failed opening counts towards the attempts of the reconnections',
    () async {
      final transport = script([
        status(503),
        status(503),
        ok(''),
        ok(''),
      ]);
      final result = await open(
        transport,
        sse: const SseOptions(reconnect: true, maxAttempts: 3),
      );
      final items = await (result as Success<Stream<SseItem<String>>, String>)
          .data
          .toList();
      expect(items.first, isA<SseReconnecting<String>>());
      expect((items.first as SseReconnecting<String>).attempt, 3);
      expect(items.last, isA<SseDisconnected<String>>());
      expect(transport.requests, hasLength(4));
    },
  );

  test("the user's Last-Event-ID is sent on every attempt", () async {
    final transport = script([status(503), ok('data: a\n\n')]);
    await watch.open(
      transport,
      sse: retry,
      headers: {'Last-Event-ID': '42'},
    );
    expect(transport.requests, hasLength(2));
    for (final request in transport.requests) {
      expect(FakeTransport.header(request, 'Last-Event-ID'), '42');
    }
  });
}
