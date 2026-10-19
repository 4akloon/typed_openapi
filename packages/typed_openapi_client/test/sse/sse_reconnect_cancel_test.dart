import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/gated_transport.dart';

/// An event-stream response with [text] that then closes.
TransportResponse _stream(String text) =>
    FakeTransport.response(text, 200, 'text/event-stream');

/// A signal that counts how often a listener is attached to it.
final class _CountingSignal extends CancelSignal {
  int whenCancelledCalls = 0;

  @override
  Future<void> get whenCancelled {
    whenCancelledCalls++;
    return super.whenCancelled;
  }
}

void main() {
  const watch = OperationRequest(
    OperationInfo(operationId: 'watch', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200},
  );

  Result<Stream<SseItem<String>>, String> decodeError(RawResponse r) =>
      r.undocumented();

  Future<Stream<SseItem<String>>> open(
    GatedTransport adapter, {
    SseOptions? sse,
    CancelSignal? token,
  }) async {
    final result = await ClientSender(adapter).openEvents(
      watch,
      (m) => m.data,
      decodeError,
      call: CallOptions(
        sse: sse ?? SseOptions(wait: (_) async {}),
        cancel: token,
      ),
      reconnection: .onRequest,
    );
    return (result as Success<Stream<SseItem<String>>, String>).data;
  }

  test('a listener that cancels during a reopen aborts that request', () async {
    final gate = Completer<void>();
    final adapter = GatedTransport((options, index) async {
      if (index == 0) return _stream('data: a\n\n');
      await gate.future;
      return _stream('data: b\n\n');
    });
    final stream = await open(
      adapter,
      sse: SseOptions(wait: (_) async {}, reconnect: true),
    );
    final subscription = stream.listen((_) {});
    await adapter.started(1);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.cancelsFired, [true, true]);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, hasLength(2), reason: 'it did not reconnect');
  });

  test(
    'a listener that cancels during the default wait stops its timer',
    () async {
      final timers = <Duration, bool>{};
      final adapter = GatedTransport(
        (options, index) async => _stream('data: a\n\n'),
      );
      await runZoned(
        () async {
          final stream = await open(
            adapter,
            sse: const SseOptions(reconnect: true),
          );
          final done = Completer<void>();
          late final StreamSubscription<SseItem<String>> subscription;
          subscription = stream.listen((item) {
            if (item is SseReconnecting) {
              subscription.cancel().then((_) => done.complete());
            }
          });
          await done.future;
          await Future<void>.delayed(Duration.zero);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == const Duration(seconds: 1)) {
              timers[duration] = false;
              return _SpyTimer(timer, () => timers[duration] = true);
            }
            return timer;
          },
        ),
      );
      expect(timers, {const Duration(seconds: 1): true});
    },
  );

  test('a reconnecting call listens to its cancel token once', () async {
    var next = 0;
    final adapter = GatedTransport(
      (options, index) async =>
          next++ < 4 ? _stream('data: a\n\n') : _stream('data: z\n\n'),
    );
    final token = _CountingSignal();
    final stream = await open(
      adapter,
      sse: SseOptions(wait: (_) async {}, reconnect: true, maxAttempts: 2),
      token: token,
    );
    final subscription = stream.listen((_) {});
    await adapter.started(4);
    await subscription.cancel();
    // The reconnector's own listener and the one that links the connections.
    expect(token.whenCancelledCalls, lessThanOrEqualTo(2));
  });
}

/// A timer that tells when it is cancelled.
final class _SpyTimer implements Timer {
  _SpyTimer(this._timer, this._onCancel);

  final Timer _timer;
  final void Function() _onCancel;

  @override
  void cancel() {
    _onCancel();
    _timer.cancel();
  }

  @override
  bool get isActive => _timer.isActive;

  @override
  int get tick => _timer.tick;
}
