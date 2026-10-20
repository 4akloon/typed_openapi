import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/watch_opening.dart';

void main() {
  const retrying = SseOptions(reconnect: true);

  /// Answers from [answers] in order, without the cancel wiring of
  /// `FakeTransport`, which hangs under `fakeAsync`.
  _Direct script(List<TransportResponse> answers) {
    var i = 0;
    return _Direct((_) => answers[i < answers.length ? i++ : i - 1]);
  }

  Future<Result<Stream<SseItem<String>>, String>> open(
    ClientTransport transport, {
    CancelSignal? cancel,
    void Function(SseTrace)? onTrace,
    SseOptions sse = retrying,
  }) => WatchOpening().open(
    transport,
    cancel: cancel,
    sse: SseOptions(onTrace: onTrace).merge(sse),
  );

  test('a cancel during the open backoff completes with Cancelled at once and '
      'leaves no timer', () {
    fakeAsync((async) {
      final transport = script([WatchOpening.status(503)]);
      final cancel = CancelSignal();
      Result<Object?, Object?>? result;
      // No wait override: the default CancellableWait runs.
      unawaited(
        ClientSender(transport)
            .openEvents<String, String>(
              WatchOpening.get,
              (m) => m.data,
              (r) => r.undocumented(),
              call: CallOptions(cancel: cancel, sse: retrying),
            )
            .then((r) => result = r),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(result, isNull);
      cancel.cancel();
      async.flushMicrotasks();
      expect(result, isA<Cancelled<Object?, Object?>>());
      expect(async.pendingTimers, isEmpty);
      expect(transport.requests, 1);
    });
  });

  test('a cancel before the first attempt returns Cancelled', () async {
    final transport = script([WatchOpening.status(503)]);
    final cancel = CancelSignal()..cancel();
    expect(
      await open(transport, cancel: cancel),
      isA<Cancelled<Object?, Object?>>(),
    );
    expect(transport.requests, 0);
  });

  group('the trace sequence', () {
    String describe(SseTrace t) => switch (t.kind) {
      .connect => 'connect ${t.attempt}',
      .open => 'open ${t.statusCode}',
      .event => 'event',
      .heartbeat => 'heartbeat',
      .error => 'error',
      .reconnecting => 'reconnecting ${t.attempt} ${t.delay!.inSeconds}s',
      .closed => 'closed',
    };

    test('of a retried opening', () async {
      final traces = <String>[];
      final transport = script([
        WatchOpening.status(503),
        WatchOpening.stream(''),
      ]);
      final result = await open(
        transport,
        sse: const SseOptions(retryOpen: true),
        onTrace: (t) => traces.add(describe(t)),
      );
      expect(traces, [
        'connect 1',
        'open 503',
        'error',
        'reconnecting 1 1s',
        'connect 2',
        'open 200',
      ]);
      await (result as Success<Stream<SseItem<String>>, String>).data
          .take(1)
          .toList();
      await Future<void>.delayed(Duration.zero);
      expect(traces.last, 'closed');
    });

    test('of a final failure', () async {
      final traces = <String>[];
      await open(
        script([WatchOpening.status(404)]),
        onTrace: (t) => traces.add(describe(t)),
      );
      expect(traces, ['connect 1', 'open 404', 'error', 'closed']);
    });

    test('when the attempts are used up', () async {
      final traces = <String>[];
      await open(
        script([WatchOpening.status(503)]),
        sse: const SseOptions(retryOpen: true, maxAttempts: 1),
        onTrace: (t) => traces.add(describe(t)),
      );
      expect(traces.sublist(traces.length - 3), [
        'open 503',
        'error',
        'closed',
      ]);
    });
  });
}

final class _Direct implements ClientTransport {
  _Direct(this._respond);

  final TransportResponse Function(TransportRequest request) _respond;
  int requests = 0;

  @override
  Future<TransportResponse> send(TransportRequest request) {
    requests++;
    return Future.value(_respond(request));
  }
}
