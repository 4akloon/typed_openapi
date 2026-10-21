import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/scripted_transport.dart';

void main() {
  const plain = OperationRequest(
    OperationInfo(operationId: 'p', method: 'GET', pathTemplate: '/p'),
  );
  const stream = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  Result<String, Never> decode(RawResponse r) => r.undocumented();

  Future<Result<Stream<SseItem<String>>, Never>> openStream(
    ClientTransport transport,
    CallOptions defaults, [
    CallOptions? call,
  ]) => ClientSender(transport, defaults: defaults).openEvents<String, Never>(
    stream,
    (m) => m.data,
    (r) => r.undocumented(),
    call: call,
  );

  /// Opens the stream and collects its items.
  List<SseItem<String>> collect(
    Future<Result<Stream<SseItem<String>>, Never>> result,
  ) {
    final items = <SseItem<String>>[];
    unawaited(
      result.then((r) {
        if (r case Success(:final data)) data.listen(items.add);
      }),
    );
    return items;
  }

  test('defaults apply when the call passes no options', () async {
    final transport = FakeTransport.text(200, '', 'text/event-stream');
    const defaults = CallOptions(headers: {'X-Env': 'prod'});
    await ClientSender(transport, defaults: defaults).send(plain, decode);
    final result = await openStream(transport, defaults);
    if (result case Success(:final data)) await data.drain<void>();
    expect(transport.requests, hasLength(2));
    for (final request in transport.requests) {
      expect(FakeTransport.header(request, 'X-Env'), 'prod');
    }
  });

  test('a null call header removes a default header on the wire', () async {
    final transport = FakeTransport.text(200, '', 'text/event-stream');
    const defaults = CallOptions(headers: {'X-Env': 'prod'});
    const call = CallOptions(headers: {'x-env': null});
    await ClientSender(
      transport,
      defaults: defaults,
    ).send(plain, decode, call: call);
    final result = await openStream(transport, defaults, call);
    if (result case Success(:final data)) await data.drain<void>();
    for (final request in transport.requests) {
      expect(FakeTransport.header(request, 'X-Env'), isNull);
    }
  });

  test('a call that sets only reconnect: false keeps the default handshake '
      'timeout', () {
    fakeAsync((async) {
      final transport = ScriptedTransport([ScriptedConnection.hanging()]);
      Result<Stream<SseItem<String>>, Never>? result;
      openStream(
        transport,
        const CallOptions(
          sse: SseOptions(handshakeTimeout: Duration(seconds: 30)),
        ),
        const CallOptions(sse: SseOptions(reconnect: false)),
      ).then((r) => result = r);
      async.elapse(const Duration(seconds: 30));
      expect(result, isA<Failure<Stream<SseItem<String>>, Never>>());
      final failure = result! as TransportError<Stream<SseItem<String>>, Never>;
      expect(failure.exception.kind, TransportExceptionKind.timeout);
    });
  });

  test('Duration.zero in the call switches off the default handshake '
      'timeout', () {
    fakeAsync((async) {
      final transport = ScriptedTransport([ScriptedConnection.hanging()]);
      Result<Stream<SseItem<String>>, Never>? result;
      openStream(
        transport,
        const CallOptions(
          sse: SseOptions(handshakeTimeout: Duration(seconds: 30)),
        ),
        const CallOptions(sse: SseOptions(handshakeTimeout: Duration.zero)),
      ).then((r) => result = r);
      async.elapse(const Duration(minutes: 10));
      expect(result, isNull);
    });
  });

  test('SseCooldown.none in the call switches off the default cooldown', () {
    fakeAsync((async) {
      final transport = ScriptedTransport([
        for (var i = 0; i < 6; i++) ScriptedConnection.open(),
      ]);
      final waits = <Duration>[];
      Future<void> wait(Duration d) {
        waits.add(d);
        return Future.value();
      }

      final items = collect(
        openStream(
          transport,
          const CallOptions(
            sse: SseOptions(
              reconnect: true,
              cooldown: SseCooldown(after: 1, duration: Duration(minutes: 5)),
              wait: null,
            ),
          ),
          CallOptions(
            sse: SseOptions(cooldown: SseCooldown.none, wait: wait),
          ),
        ),
      );
      async.flushMicrotasks();
      for (var i = 0; i < 3; i++) {
        transport.connections[i].body.close();
        async.flushMicrotasks();
      }
      expect(items, isNotEmpty);
      expect(waits.take(2), [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(waits, isNot(contains(const Duration(minutes: 5))));
    });
  });

  group('maxAttempts', () {
    /// Drops [drops] connections in a row and returns the requests made.
    int requestsAfterDrops(
      FakeAsync async,
      CallOptions defaults,
      CallOptions? call,
      int drops,
    ) {
      final transport = ScriptedTransport([
        for (var i = 0; i < drops + 2; i++) ScriptedConnection.open(),
      ]);
      collect(openStream(transport, defaults, call));
      async.flushMicrotasks();
      for (var i = 0; i < drops; i++) {
        if (i >= transport.requests.length) break;
        transport.connections[i].body.close();
        async.elapse(const Duration(minutes: 1));
      }
      return transport.requests.length;
    }

    test('an omitted value inherits the default', () {
      fakeAsync((async) {
        final requests = requestsAfterDrops(
          async,
          const CallOptions(sse: SseOptions(maxAttempts: 2)),
          const CallOptions(sse: SseOptions(reconnect: true)),
          7,
        );
        expect(requests, 3);
      });
    });

    test('null in the call means unlimited', () {
      fakeAsync((async) {
        final requests = requestsAfterDrops(
          async,
          const CallOptions(sse: SseOptions(maxAttempts: 2)),
          const CallOptions(
            sse: SseOptions(reconnect: true, maxAttempts: null),
          ),
          7,
        );
        expect(requests, 8);
      });
    });

    test('null in the defaults is inherited by a call without it', () {
      fakeAsync((async) {
        final requests = requestsAfterDrops(
          async,
          const CallOptions(sse: SseOptions(maxAttempts: null)),
          const CallOptions(sse: SseOptions(reconnect: true)),
          7,
        );
        expect(requests, 8);
      });
    });
  });

  group('cancel', () {
    test('a default cancel signal cancels a call without its own', () async {
      final signal = CancelSignal()..cancel();
      final transport = FakeTransport.json(200, 'x');
      final result = await ClientSender(
        transport,
        defaults: CallOptions(cancel: signal),
      ).send(plain, decode);
      expect(result, isA<Cancelled<String, Never>>());
    });

    test('a call with a signal of its own still runs', () async {
      final signal = CancelSignal()..cancel();
      final transport = FakeTransport.json(200, 'x');
      final result =
          await ClientSender(
            transport,
            defaults: CallOptions(cancel: signal),
          ).send<String, Never>(
            plain,
            (r) => Success(r.json as String, statusCode: r.statusCode),
            call: CallOptions(cancel: CancelSignal()),
          );
      expect(result, isA<Success<String, Never>>());
    });
  });

  test('a default cancel fired during the opening backoff completes the '
      'Future with Cancelled and leaves no wait pending', () {
    fakeAsync((async) {
      final signal = CancelSignal();
      final failing = ScriptedConnection.open(status: 503);
      final transport = ScriptedTransport([failing]);
      Result<Stream<SseItem<String>>, Never>? result;
      openStream(
        transport,
        CallOptions(
          cancel: signal,
          sse: const SseOptions(reconnect: true),
        ),
      ).then((r) => result = r);
      async.flushMicrotasks();
      failing.body.close();
      async.flushMicrotasks();
      expect(result, isNull);
      expect(async.pendingTimers, isNotEmpty);
      signal.cancel();
      async.flushMicrotasks();
      expect(result, isA<Cancelled<Stream<SseItem<String>>, Never>>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('ClientSender without defaults sends as before', () async {
    final transport = FakeTransport.json(200, 'x');
    final result = await ClientSender(transport).send<String, Never>(
      plain,
      (r) => Success(r.json as String, statusCode: r.statusCode),
    );
    expect(result, isA<Success<String, Never>>());
    expect(ClientSender(transport).defaults.headers, isEmpty);
  });
}
