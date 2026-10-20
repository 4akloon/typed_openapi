import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/gated_transport.dart';

/// An event-stream response with [text] that then closes.
TransportResponse _stream(String text, [int status = 200]) =>
    FakeTransport.response(text, status, 'text/event-stream');

/// Answers the requests in order with [answers]; the last one repeats.
FakeTransport _adapter(
  List<TransportResponse Function(TransportRequest)> answers,
) {
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

  Result<Stream<SseItem<String>>, String> decodeError(RawResponse r) =>
      r.undocumented();

  String describe(SseItem<String> item) => switch (item) {
    SseEvent(:final data) => 'event $data',
    SseDecodeError() => 'decode error',
    SseReconnecting(:final attempt, :final delay) =>
      'reconnecting $attempt after ${delay.inMilliseconds}ms',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  /// The stream of a [watch] that reconnects, opened through [adapter].
  Future<Stream<SseItem<String>>> open(
    ClientTransport adapter,
    SseOptions options,
  ) async {
    final result = await ClientSender(adapter).openEvents(
      watch,
      (m) => m.data,
      decodeError,
      call: CallOptions(sse: options),
      reconnection: SseReconnection.on,
    );
    return (result as Success<Stream<SseItem<String>>, String>).data;
  }

  /// The items of the stream, as [describe] says.
  Future<List<String>> items(Stream<SseItem<String>> stream) async => [
    for (final item in await stream.toList()) describe(item),
  ];

  SseOptions options({
    int maxAttempts = 5,
    Duration delay = const Duration(seconds: 1),
    List<Duration>? waits,
  }) => SseOptions(
    reconnect: true,
    maxAttempts: maxAttempts,
    delay: delay,
    wait: (d) async => waits?.add(d),
  );

  test('the first wait of a call is its delay', () async {
    final waits = <Duration>[];
    final stream = await open(
      _adapter([(_) => _stream('data: a\n\n'), (_) => _stream('', 204)]),
      options(delay: const Duration(seconds: 2), waits: waits),
    );
    await items(stream);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('a server retry over the cap is the wait through the stream', () async {
    final waits = <Duration>[];
    final stream = await open(
      _adapter([
        (_) => _stream('retry: 120000\ndata: a\n\n'),
        (_) => _stream('', 204),
      ]),
      options(waits: waits),
    );
    await items(stream);
    expect(waits, [const Duration(minutes: 2)]);
  });

  group('the Last-Event-ID of a reconnection', () {
    Future<List<Object?>> sent(List<String> bodies) async {
      final adapter = _adapter([
        for (final body in bodies) (_) => _stream(body),
        (_) => _stream('', 204),
      ]);
      await items(await open(adapter, options()));
      return [
        for (final r in adapter.requests)
          FakeTransport.header(r, 'Last-Event-ID'),
      ];
    }

    test('ignores an id with a NUL', () async {
      expect(await sent(['id: 4\ndata: a\n\n', 'id: 5\u0000\ndata: b\n\n']), [
        null,
        '4',
        '4',
      ]);
    });

    test('is not sent after an empty id resets it', () async {
      expect(await sent(['id: 4\ndata: a\n\n', 'id:\ndata: b\n\n']), [
        null,
        '4',
        null,
      ]);
    });
  });

  group('a connection that brings no message', () {
    test('with only an id or a retry is not progress', () async {
      final adapter = _adapter([
        (_) => _stream('data: a\n\n'),
        (_) => _stream('id: 9\n\n'),
        (_) => _stream('retry: 500\n\n'),
      ]);
      final stream = await open(adapter, options(maxAttempts: 2));
      expect(await items(stream), [
        'event a',
        'reconnecting 1 after 1000ms',
        'reconnecting 2 after 2000ms',
        'end closed',
      ]);
      expect(adapter.requests, hasLength(3));
    });
  });

  group('a wait that throws', () {
    test('an Exception at once ends the stream with SseDisconnected', () async {
      final stream = await open(
        _adapter([(_) => _stream('data: a\n\n')]),
        SseOptions(
          reconnect: true,
          wait: (_) => throw const FormatException('at once'),
        ),
      );
      final errors = <Object>[];
      final items = await stream.handleError(errors.add).toList();
      expect(items.take(2).map(describe), [
        'event a',
        'reconnecting 1 after 1000ms',
      ]);
      expect(errors, isEmpty);
      expect(
        (items.last as SseDisconnected<String>).cause,
        isA<FormatException>(),
      );
    });

    test('at once ends the stream with that error', () async {
      final stream = await open(
        _adapter([(_) => _stream('data: a\n\n')]),
        SseOptions(
          reconnect: true,
          wait: (_) => throw StateError('at once'),
        ),
      );
      final seen = <String>[];
      final errors = <Object>[];
      await stream
          .handleError(errors.add)
          .forEach((item) => seen.add(describe(item)));
      expect(seen, ['event a', 'reconnecting 1 after 1000ms']);
      expect(errors.single, isA<StateError>());
    });
  });

  test('a pause during the reopen holds the next connection', () async {
    final gate = Completer<void>();
    final adapter = GatedTransport((options, index) async {
      if (index == 0) return _stream('data: a\n\n');
      if (index == 1) {
        await gate.future;
        return _stream('data: b\n\n');
      }
      return _stream('', 204);
    });
    final stream = await open(adapter, options());
    final seen = <String>[];
    final done = Completer<void>();
    final subscription = stream.listen(
      (item) => seen.add(describe(item)),
      onDone: done.complete,
    );
    addTearDown(subscription.cancel);
    await adapter.started(1);
    subscription.pause();
    gate.complete();
    await pumpEventQueue();
    expect(seen, ['event a', 'reconnecting 1 after 1000ms']);
    expect(seen, isNot(contains('event b')), reason: 'held while paused');
    subscription.resume();
    await done.future.timeout(const Duration(seconds: 2));
    expect(seen, contains('event b'));
  });
}
