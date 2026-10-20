import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/scripted_transport.dart';

void main() {
  const request = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  /// Opens the stream inside a [fakeAsync] zone and collects its items.
  ({
    List<SseItem<String>> items,
    Future<Result<Stream<SseItem<String>>, Never>> result,
  })
  open(
    ScriptedTransport transport,
    SseOptions sse, {
    CancelSignal? cancel,
  }) {
    final items = <SseItem<String>>[];
    final result = ClientSender(transport).openEvents<String, Never>(
      request,
      (m) => m.data,
      (r) => r.undocumented(),
      call: CallOptions(sse: sse, cancel: cancel),
    );
    unawaited(
      result.then((r) {
        if (r case Success(:final data)) data.listen(items.add);
      }),
    );
    return (items: items, result: result);
  }

  TransportException? causeOf(SseItem<String> item) => switch (item) {
    SseDisconnected(:final cause) => cause as TransportException?,
    SseReconnecting(:final cause) => cause as TransportException?,
    _ => null,
  };

  const idle = Duration(minutes: 3);

  group('idle timeout', () {
    test('ends a stream without reconnection and cancels the request', () {
      fakeAsync((async) {
        final transport = ScriptedTransport([ScriptedConnection.open()]);
        final stream = open(transport, const SseOptions(idleTimeout: idle));
        async.elapse(idle - const Duration(seconds: 1));
        expect(stream.items, isEmpty);
        expect(transport.cancelsFired, [false]);
        async.elapse(const Duration(seconds: 1));
        expect(stream.items, hasLength(1));
        expect(
          causeOf(stream.items.single)?.kind,
          TransportExceptionKind.timeout,
        );
        expect(transport.cancelsFired, [true]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('reconnects with a timeout cause when reconnection is on', () {
      fakeAsync((async) {
        final transport = ScriptedTransport([
          ScriptedConnection.open(),
          ScriptedConnection.open(),
        ]);
        final stream = open(
          transport,
          const SseOptions(reconnect: true, idleTimeout: idle),
        );
        async.elapse(idle);
        final reconnecting = stream.items.single as SseReconnecting<String>;
        expect(reconnecting.cause, isA<TransportException>());
        expect(causeOf(reconnecting)?.kind, TransportExceptionKind.timeout);
        expect(transport.cancelsFired, [true]);
        async.elapse(const Duration(seconds: 1));
        expect(transport.requests, hasLength(2));
      });
    });

    test('a heartbeat comment resets the timer', () {
      fakeAsync((async) {
        final connection = ScriptedConnection.open();
        final transport = ScriptedTransport([connection]);
        final stream = open(transport, const SseOptions(idleTimeout: idle));
        for (var i = 0; i < 5; i++) {
          async.elapse(idle - const Duration(seconds: 1));
          connection.write(': ping\n');
        }
        async.elapse(idle - const Duration(seconds: 1));
        expect(stream.items, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(
          causeOf(stream.items.single)?.kind,
          TransportExceptionKind.timeout,
        );
      });
    });

    test('an event resets the timer and arrives', () {
      fakeAsync((async) {
        final connection = ScriptedConnection.open();
        final stream = open(
          ScriptedTransport([connection]),
          const SseOptions(idleTimeout: idle),
        );
        async.elapse(idle - const Duration(seconds: 1));
        connection.write('data: a\n\n');
        async.elapse(idle - const Duration(seconds: 1));
        expect(stream.items.map((i) => i.runtimeType.toString()), [
          'SseEvent<String>',
        ]);
      });
    });

    test('does not run while the listener is paused', () {
      fakeAsync((async) {
        final connection = ScriptedConnection.open();
        final transport = ScriptedTransport([connection]);
        final items = <SseItem<String>>[];
        late StreamSubscription<SseItem<String>> subscription;
        ClientSender(transport)
            .openEvents<String, Never>(
              request,
              (m) => m.data,
              (r) => r.undocumented(),
              call: const CallOptions(sse: SseOptions(idleTimeout: idle)),
            )
            .then((r) {
              subscription =
                  (r as Success<Stream<SseItem<String>>, Never>).data.listen(
                    items.add,
                  )..pause();
            });
        async.elapse(idle * 3);
        expect(items, isEmpty);
        subscription.resume();
        async.elapse(idle - const Duration(seconds: 1));
        expect(items, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(items, hasLength(1));
        unawaited(subscription.cancel());
      });
    });

    test('a cancel still ends the stream and aborts the request', () {
      fakeAsync((async) {
        final cancel = CancelSignal();
        final transport = ScriptedTransport([ScriptedConnection.open()]);
        final stream = open(
          transport,
          const SseOptions(reconnect: true, idleTimeout: idle),
          cancel: cancel,
        );
        async.elapse(const Duration(seconds: 5));
        cancel.cancel('stop');
        async.elapse(const Duration(seconds: 1));
        expect(transport.cancelsFired, [true]);
        expect(
          causeOf(stream.items.last)?.kind,
          TransportExceptionKind.cancelled,
        );
        expect(stream.items.last, isA<SseDisconnected<String>>());
        async.elapse(idle * 2);
        expect(transport.requests, hasLength(1));
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('a listener that cancels leaves no timer', () {
      fakeAsync((async) {
        final transport = ScriptedTransport([ScriptedConnection.open()]);
        late StreamSubscription<SseItem<String>> subscription;
        ClientSender(transport)
            .openEvents<String, Never>(
              request,
              (m) => m.data,
              (r) => r.undocumented(),
              call: const CallOptions(sse: SseOptions(idleTimeout: idle)),
            )
            .then((r) {
              subscription = (r as Success<Stream<SseItem<String>>, Never>).data
                  .listen((_) {});
            });
        async.elapse(const Duration(seconds: 5));
        unawaited(subscription.cancel());
        async.flushMicrotasks();
        expect(transport.cancelsFired, [true]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  });

  group('handshake timeout', () {
    const handshake = Duration(seconds: 30);

    test('a first connection that does not answer is a TransportError', () {
      fakeAsync((async) {
        final transport = ScriptedTransport([ScriptedConnection.hanging()]);
        Result<Stream<SseItem<String>>, Never>? result;
        open(
          transport,
          const SseOptions(handshakeTimeout: handshake),
        ).result.then((r) => result = r);
        async.elapse(handshake - const Duration(seconds: 1));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 1));
        final error = result as TransportError;
        expect(error.exception.kind, TransportExceptionKind.timeout);
        expect(transport.cancelsFired, [true]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    for (final honours in [false, true]) {
      test(
        'a cancel during the first handshake ends it at once '
        '(transport honours the cancel: $honours)',
        () {
          fakeAsync((async) {
            final cancel = CancelSignal();
            final transport = ScriptedTransport([
              ScriptedConnection.hanging(honoursCancel: honours),
            ]);
            Result<Stream<SseItem<String>>, Never>? result;
            open(
              transport,
              const SseOptions(handshakeTimeout: handshake),
              cancel: cancel,
            ).result.then((r) => result = r);
            async.elapse(const Duration(seconds: 2));
            cancel.cancel('stop');
            async.flushMicrotasks();
            expect(result, isA<Cancelled<Stream<SseItem<String>>, Never>>());
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );

      test(
        'a cancel during a reconnect handshake ends the stream '
        '(transport honours the cancel: $honours)',
        () {
          fakeAsync((async) {
            final cancel = CancelSignal();
            final first = ScriptedConnection.open();
            final transport = ScriptedTransport([
              first,
              ScriptedConnection.hanging(honoursCancel: honours),
            ]);
            final stream = open(
              transport,
              const SseOptions(reconnect: true, handshakeTimeout: handshake),
              cancel: cancel,
            );
            first.body.close();
            async.elapse(const Duration(seconds: 2));
            expect(transport.requests, hasLength(2));
            cancel.cancel('stop');
            async.flushMicrotasks();
            expect(stream.items.last, isA<SseDisconnected<String>>());
            expect(
              causeOf(stream.items.last)?.kind,
              TransportExceptionKind.cancelled,
            );
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );
    }

    test('a response after the timeout has its body cancelled', () {
      fakeAsync((async) {
        final late = ScriptedConnection.hanging();
        var isCancelled = false;
        late.body.onCancel = () => isCancelled = true;
        final transport = ScriptedTransport([late]);
        open(transport, const SseOptions(handshakeTimeout: handshake));
        async.elapse(handshake);
        late.answerNow();
        async.flushMicrotasks();
        expect(isCancelled, isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('failed handshakes count toward maxAttempts', () {
      fakeAsync((async) {
        final first = ScriptedConnection.open();
        final transport = ScriptedTransport([
          first,
          ScriptedConnection.hanging(),
          ScriptedConnection.hanging(),
        ]);
        final stream = open(
          transport,
          const SseOptions(
            reconnect: true,
            maxAttempts: 2,
            handshakeTimeout: handshake,
          ),
        );
        first.body.close();
        async.elapse(const Duration(minutes: 5));
        expect(transport.requests, hasLength(3));
        final last = stream.items.last as SseDisconnected<String>;
        expect(causeOf(last)?.kind, TransportExceptionKind.timeout);
        expect(
          stream.items.whereType<SseReconnecting<String>>().map(
            (r) => r.attempt,
          ),
          [1, 2],
        );
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('a reconnection that does not answer is another attempt', () {
      fakeAsync((async) {
        final first = ScriptedConnection.open();
        final transport = ScriptedTransport([
          first,
          ScriptedConnection.hanging(),
          ScriptedConnection.open(status: 204),
        ]);
        final stream = open(
          transport,
          const SseOptions(reconnect: true, handshakeTimeout: handshake),
        );
        first.body.close();
        async.elapse(const Duration(seconds: 1));
        expect(transport.requests, hasLength(2));
        async.elapse(handshake);
        expect(transport.cancelsFired[1], isTrue);
        final reconnecting = stream.items.whereType<SseReconnecting<String>>();
        expect(reconnecting.map((r) => r.attempt), [1, 2]);
        expect(
          causeOf(reconnecting.last)?.kind,
          TransportExceptionKind.timeout,
        );
        async.elapse(const Duration(seconds: 2));
        expect(transport.requests, hasLength(3));
        expect(stream.items.last, isA<SseDisconnected<String>>());
      });
    });

    test('an answer in time is not affected', () {
      fakeAsync((async) {
        final stream = open(
          ScriptedTransport([ScriptedConnection.open()]),
          const SseOptions(handshakeTimeout: handshake),
        );
        async.elapse(handshake * 2);
        expect(stream.items, isEmpty);
      });
    });
  });

  group('cooldown', () {
    test('a cancel during the cooldown wait leaves no timer', () {
      fakeAsync((async) {
        final cancel = CancelSignal();
        final first = ScriptedConnection.open();
        final transport = ScriptedTransport([
          first,
          ScriptedConnection.hanging(),
        ]);
        final stream = open(
          transport,
          const SseOptions(
            reconnect: true,
            handshakeTimeout: Duration(seconds: 10),
            cooldown: SseCooldown(after: 1, duration: Duration(minutes: 5)),
          ),
          cancel: cancel,
        );
        first.body.close();
        // Attempt 1 never answers and fails by the handshake timeout; the
        // next wait is the cooldown.
        async.elapse(const Duration(seconds: 15));
        expect(
          stream.items.whereType<SseReconnecting<String>>().last.delay,
          const Duration(minutes: 5),
        );
        cancel.cancel('stop');
        async.flushMicrotasks();
        expect(stream.items.last, isA<SseDisconnected<String>>());
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  });
}
