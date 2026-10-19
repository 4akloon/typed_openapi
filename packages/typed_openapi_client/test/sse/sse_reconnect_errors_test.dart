import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

/// An event-stream response with [text] that then closes.
TransportResponse _stream(String text) =>
    FakeTransport.response(text, 200, 'text/event-stream');

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
    SseEvent(:final data, :final id) => 'event $data #$id',
    SseDecodeError() => 'decode error',
    SseReconnecting(:final attempt, :final delay) =>
      'reconnecting $attempt after ${delay.inMilliseconds}ms',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  /// The stream of a [watch] that reconnects, opened through [adapter].
  Future<Stream<SseItem<String>>> open(
    FakeTransport adapter, {
    SseOptions options = const SseOptions(reconnect: true),
  }) async {
    final result = await ClientSender(adapter).openEvents(
      watch,
      (m) => m.data,
      decodeError,
      call: CallOptions(sse: options),
      reconnection: SseReconnection.on,
    );
    return (result as Success<Stream<SseItem<String>>, String>).data;
  }

  /// What [stream] gives until it ends, an error shown as `error ...`, and
  /// the errors that escaped to the zone of [body].
  Future<(List<String>, List<Object>)> collect(
    Future<Stream<SseItem<String>>> Function() body,
  ) async {
    final seen = <String>[];
    final escaped = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(
      () async {
        final stream = await body();
        stream.listen(
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

  group('an Error on a reconnect attempt', () {
    test('of the wait is the error of the stream, not of the zone', () async {
      final (seen, escaped) = await collect(
        () => open(
          _adapter([(_) => _stream('data: a\n\n')]),
          options: SseOptions(
            reconnect: true,
            wait: (_) async => throw StateError('boom'),
          ),
        ),
      );
      expect(seen, [
        'event a #',
        'reconnecting 1 after 1000ms',
        'error Bad state: boom',
      ]);
      expect(escaped, isEmpty);
    });

    test(
      'of the request is the error of the stream, not of the zone',
      () async {
        final (seen, escaped) = await collect(
          () => open(
            _adapter([
              (_) => _stream('data: a\n\n'),
              (_) => throw StateError('adapter'),
            ]),
            options: SseOptions(reconnect: true, wait: (_) async {}),
          ),
        );
        expect(seen, [
          'event a #',
          'reconnecting 1 after 1000ms',
          'error Bad state: adapter',
        ]);
        expect(escaped, isEmpty);
      },
    );
  });

  test('a pause during the wait holds the next connection', () async {
    final wait = Completer<void>();
    final adapter = _adapter([
      (_) => _stream('data: a\n\n'),
      (_) => _stream('data: b\n\n'),
      (_) => FakeTransport.response('', 204),
    ]);
    final stream = await open(
      adapter,
      options: SseOptions(reconnect: true, wait: (_) => wait.future),
    );
    final seen = <String>[];
    final done = Completer<void>();
    final subscription = stream.listen(
      (item) => seen.add(describe(item)),
      onDone: done.complete,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen, ['event a #', 'reconnecting 1 after 1000ms']);
    subscription.pause();
    wait.complete();
    await pumpEventQueue();
    expect(adapter.requests, hasLength(2));
    expect(seen, hasLength(2), reason: 'nothing arrives while paused');
    subscription.resume();
    await done.future.timeout(const Duration(seconds: 2));
    expect(seen, contains('event b #'));
  });

  test('an event id that is not a header value is not sent', () async {
    final adapter = _adapter([
      (_) => _stream('id: ідентифікатор\ndata: a\n\n'),
      (_) => _stream('data: b\n\n'),
      (_) => FakeTransport.response('', 204),
    ]);
    final stream = await open(
      adapter,
      options: SseOptions(reconnect: true, wait: (_) async {}),
    );
    expect((await stream.toList()).map(describe), [
      'event a #ідентифікатор',
      'reconnecting 1 after 1000ms',
      'event b #ідентифікатор',
      'reconnecting 1 after 1000ms',
      'end closed',
    ]);
    for (final request in adapter.requests) {
      expect(FakeTransport.header(request, 'Last-Event-ID'), isNull);
    }
    expect(adapter.requests, hasLength(3));
  });

  test('an event id of printable ASCII is sent as it is', () async {
    final adapter = _adapter([
      (_) => _stream('id: a b~9\ndata: a\n\n'),
      (_) => FakeTransport.response('', 204),
    ]);
    final stream = await open(
      adapter,
      options: SseOptions(reconnect: true, wait: (_) async {}),
    );
    await stream.toList();
    expect(FakeTransport.header(adapter.requests[1], 'Last-Event-ID'), 'a b~9');
  });
}
