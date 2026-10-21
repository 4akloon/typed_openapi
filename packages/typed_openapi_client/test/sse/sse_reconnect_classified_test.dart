import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

typedef _Answer = TransportResponse Function(TransportRequest);

/// An event-stream response with [text] that then closes.
TransportResponse _stream(String text) =>
    FakeTransport.response(text, 200, 'text/event-stream');

/// A response with [status] and [headers].
TransportResponse _status(
  int status, {
  Map<String, List<String>> headers = const {},
  String body = 'x',
}) => TransportResponse(
  statusCode: status,
  body: Stream.value(body.codeUnits),
  headers: headers,
);

/// Answers the requests in order with [answers]; the last one repeats.
FakeTransport _adapter(List<_Answer> answers) {
  var next = 0;
  return FakeTransport(
    (options) => answers[next < answers.length - 1 ? next++ : next](options),
  );
}

void main() {
  const watch = OperationRequest(
    OperationInfo(operationId: 'watch', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );
  final noWait = SseOptions(reconnect: true, wait: (_) async {});

  Result<Stream<SseItem<String>>, String> undocumented(RawResponse r) =>
      r.undocumented();

  String describe(SseItem<String> item) => switch (item) {
    SseEvent(:final data, :final id) => 'event $data #$id',
    SseDecodeError() => 'decode error',
    SseReconnecting(:final attempt, :final delay) =>
      'reconnecting $attempt after ${delay.inMilliseconds}ms',
    SseDisconnected(cause: TransportException(:final kind)) => 'end $kind',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  /// What a reconnecting [watch] gives until it ends, and the errors that
  /// escaped to the zone.
  Future<(List<String>, List<Object>)> run(
    FakeTransport adapter, {
    SseOptions? options,
    CancelSignal? cancel,
    Result<Stream<SseItem<String>>, String> Function(RawResponse)? decoder,
  }) async {
    final seen = <String>[];
    final escaped = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(
      () async {
        final result = await ClientSender(adapter).openEvents(
          watch,
          (m) => m.data,
          decoder ?? undocumented,
          call: CallOptions(sse: options ?? noWait, cancel: cancel),
          reconnection: SseReconnection.on,
        );
        (result as Success<Stream<SseItem<String>>, String>).data.listen(
          (item) => seen.add(describe(item)),
          onError: (Object error) => seen.add('error $error'),
          onDone: finished.complete,
        );
      },
      (error, _) {
        escaped.add(error);
        if (!finished.isCompleted) finished.complete();
      },
    );
    await finished.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => seen.add('hung'),
    );
    return (seen, escaped);
  }

  final first = [(_) => _stream('data: a\n\n')];

  test('a 502 on a reconnection continues', () async {
    final (seen, escaped) = await run(
      _adapter([
        ...first,
        (_) => _status(502),
        (_) => _stream('data: b\n\n'),
        (_) => FakeTransport.response('', 204),
      ]),
    );
    expect(seen, [
      'event a #',
      'reconnecting 1 after 1000ms',
      'reconnecting 2 after 2000ms',
      'event b #',
      'reconnecting 1 after 1000ms',
      'end closed',
    ]);
    expect(escaped, isEmpty);
  });

  test('a documented 503 (HttpError) continues', () async {
    final (seen, _) = await run(
      _adapter([
        ...first,
        (_) => _status(503),
        (_) => FakeTransport.response('', 204),
      ]),
      decoder: (r) => HttpError('busy', statusCode: 503, headers: r.headers),
    );
    expect(seen, [
      'event a #',
      'reconnecting 1 after 1000ms',
      'reconnecting 2 after 2000ms',
      'end closed',
    ]);
  });

  test('a 401 ends with SseDisconnected(cause: HttpError 401)', () async {
    final (seen, _) = await run(
      _adapter([...first, (_) => _status(401)]),
      decoder: (r) => r.statusCode == 401
          ? HttpError('no', statusCode: 401, headers: r.headers)
          : r.undocumented(),
    );
    expect(seen, [
      'event a #',
      'reconnecting 1 after 1000ms',
      'end HttpError(401)',
    ]);
  });

  for (final status in [404, 501]) {
    test('a $status ends the stream', () async {
      final (seen, _) = await run(_adapter([...first, (_) => _status(status)]));
      expect(seen, hasLength(3));
      expect(seen.last, startsWith('end '));
      expect(seen.last, contains('$status'));
    });
  }

  test('a DecodeError with status 503 continues', () async {
    final (seen, _) = await run(
      _adapter([
        ...first,
        (_) => _status(
          503,
          body: '<html>',
          headers: {
            'content-type': ['application/json'],
          },
        ),
        (_) => FakeTransport.response('', 204),
      ]),
      decoder: (r) => DecodeError(
        JsonDecodeException(expected: 'object', actual: 'html'),
        statusCode: r.statusCode,
        headers: r.headers,
      ),
    );
    expect(seen, [
      'event a #',
      'reconnecting 1 after 1000ms',
      'reconnecting 2 after 2000ms',
      'end closed',
    ]);
  });

  group('Retry-After on a 429 reconnection', () {
    Future<List<String>> after(String value, {SseOptions? options}) async {
      final (seen, _) = await run(
        _adapter([
          ...first,
          (_) => _status(
            429,
            headers: {
              'retry-after': [value],
            },
          ),
          (_) => FakeTransport.response('', 204),
        ]),
        options: options,
      );
      return seen;
    }

    test('7 waits 7 s', () async {
      expect(await after('7'), [
        'event a #',
        'reconnecting 1 after 1000ms',
        'reconnecting 2 after 7000ms',
        'end closed',
      ]);
    });

    test('1 waits for the larger backoff', () async {
      expect(await after('1'), contains('reconnecting 2 after 2000ms'));
    });

    test('above maxDelay is not capped', () async {
      final seen = await after(
        '120',
        options: SseOptions(
          reconnect: true,
          maxDelay: const Duration(seconds: 30),
          wait: (_) async {},
        ),
      );
      expect(seen, contains('reconnecting 2 after 120000ms'));
    });
  });

  group('a TransportError', () {
    Future<List<String>> ofKind(TransportExceptionKind kind) async {
      final (seen, _) = await run(
        _adapter([
          ...first,
          (_) => throw TransportException(kind, 'x'),
          (_) => FakeTransport.response('', 204),
        ]),
      );
      return seen;
    }

    test('of kind other ends the stream', () async {
      expect(await ofKind(.other), [
        'event a #',
        'reconnecting 1 after 1000ms',
        'end ${TransportExceptionKind.other}',
      ]);
    });

    for (final kind in [
      TransportExceptionKind.connection,
      TransportExceptionKind.timeout,
    ]) {
      test('of kind $kind continues', () async {
        expect(await ofKind(kind), [
          'event a #',
          'reconnecting 1 after 1000ms',
          'reconnecting 2 after 2000ms',
          'end closed',
        ]);
      });
    }
  });

  group('retryWhen', () {
    test('replaces the default on a reconnection', () async {
      final (extended, _) = await run(
        _adapter([
          ...first,
          (_) => throw const TransportException(.other, 'x'),
          (_) => FakeTransport.response('', 204),
        ]),
        options: SseOptions(
          reconnect: true,
          wait: (_) async {},
          retryWhen: (f) => SseRetry.isTransient(f) || f is TransportError,
        ),
      );
      expect(extended, contains('reconnecting 2 after 2000ms'));
      final (never, _) = await run(
        _adapter([...first, (_) => _status(503)]),
        options: SseOptions(
          reconnect: true,
          wait: (_) async {},
          retryWhen: (_) => false,
        ),
      );
      expect(never, hasLength(3));
      expect(never.last, startsWith('end '));
    });

    test('that throws an Exception counts as final', () async {
      final (seen, escaped) = await run(
        _adapter([...first, (_) => _status(503)]),
        options: SseOptions(
          reconnect: true,
          wait: (_) async {},
          retryWhen: (_) => throw const FormatException('bad'),
        ),
      );
      expect(seen, hasLength(3));
      expect(seen.last, startsWith('end '));
      expect(escaped, isEmpty);
    });

    test('that throws an Error is the error of the stream', () async {
      final (seen, escaped) = await run(
        _adapter([...first, (_) => _status(503)]),
        options: SseOptions(
          reconnect: true,
          wait: (_) async {},
          retryWhen: (_) => throw StateError('boom'),
        ),
      );
      expect(seen.last, 'error Bad state: boom');
      expect(escaped, isEmpty);
    });

    test('is not asked about a cancel', () async {
      final cancel = CancelSignal();
      var asked = 0;
      final (seen, _) = await run(
        _adapter(first),
        cancel: cancel,
        options: SseOptions(
          reconnect: true,
          wait: (_) {
            cancel.cancel();
            return Completer<void>().future;
          },
          retryWhen: (_) {
            asked++;
            return true;
          },
        ),
      );
      expect(seen.last, startsWith('end '));
      expect(asked, 0);
    });
  });
}
