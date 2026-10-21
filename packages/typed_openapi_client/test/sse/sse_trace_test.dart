import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/scripted_transport.dart';

void main() {
  const request = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  TransportResponse stream(String text, [int status = 200]) =>
      FakeTransport.response(text, status, 'text/event-stream');

  String describe(SseTrace t) => switch (t.kind) {
    .connect => 'connect ${t.attempt}',
    .open => 'open ${t.statusCode}',
    .event => 'event ${t.event} #${t.eventId}',
    .heartbeat => 'heartbeat',
    .error => 'error ${(t.error as TransportException).kind.name}',
    .reconnecting => 'reconnecting ${t.attempt} ${t.delay!.inSeconds}s',
    .closed => 'closed',
  };

  /// Opens `watch` over [transport]; the traces go to [traces].
  Future<List<SseItem<String>>> run(
    ClientTransport transport,
    List<SseTrace> traces, {
    bool reconnect = true,
    String Function(SseMessage)? decode,
  }) async {
    final result = await ClientSender(transport).openEvents<String, Never>(
      request,
      decode ?? (m) => m.data,
      (r) => r.undocumented(),
      call: CallOptions(
        sse: SseOptions(
          reconnect: reconnect,
          onTrace: traces.add,
          wait: (_) async {},
        ),
      ),
    );
    return (result as Success<Stream<SseItem<String>>, Never>).data.toList();
  }

  test('a stream that reconnects is traced step by step', () async {
    final traces = <SseTrace>[];
    var calls = 0;
    await run(
      FakeTransport(
        (_) => calls++ == 0
            ? stream(': hi\nid: 1\nevent: e\ndata: a\n\n')
            : stream('', 204),
      ),
      traces,
    );
    expect(traces.map(describe), [
      'connect 1',
      'open 200',
      'heartbeat',
      'event e #1',
      'reconnecting 1 1s',
      'connect 2',
      'open 204',
      'closed',
    ]);
  });

  test('every trace of a stream has its id, other streams another', () async {
    final a = <SseTrace>[];
    final b = <SseTrace>[];
    final transport = FakeTransport((_) => stream('data: x\n\n', 204));
    await run(transport, a);
    await run(transport, b);
    expect(a.map((t) => t.streamId).toSet(), hasLength(1));
    expect(b.map((t) => t.streamId).toSet(), hasLength(1));
    expect(a.first.streamId, isNot(b.first.streamId));
  });

  test('every trace carries the operation of the request', () async {
    final traces = <SseTrace>[];
    var calls = 0;
    await run(
      FakeTransport(
        (_) => calls++ == 0 ? stream('data: a\n\n') : stream('', 204),
      ),
      traces,
    );
    expect(traces, isNotEmpty);
    for (final trace in traces) {
      expect(trace.operation.operationId, 'w');
      expect(trace.operation.method, 'GET');
      expect(trace.operation.pathTemplate, '/w');
    }
  });

  test(
    'two streams of one operation have different stream ids but the same '
    'operation',
    () async {
      final a = <SseTrace>[];
      final b = <SseTrace>[];
      final transport = FakeTransport((_) => stream('data: x\n\n', 204));
      await run(transport, a);
      await run(transport, b);
      expect(a.first.streamId, isNot(b.first.streamId));
      expect(a.first.operation.operationId, b.first.operation.operationId);
    },
  );

  test('an onTrace from the client defaults names the operation', () async {
    final traces = <SseTrace>[];
    final sender = ClientSender(
      FakeTransport((_) => stream('data: x\n\n', 204)),
      defaults: CallOptions(sse: SseOptions(onTrace: traces.add)),
    );
    final result = await sender.openEvents<String, Never>(
      request,
      (m) => m.data,
      (r) => r.undocumented(),
    );
    await (result as Success<Stream<SseItem<String>>, Never>).data.toList();
    expect(traces, isNotEmpty);
    for (final trace in traces) {
      expect(trace.operation.operationId, 'w');
      expect(trace.operation.pathTemplate, '/w');
    }
  });

  test('toString names the operation', () async {
    final traces = <SseTrace>[];
    await run(FakeTransport((_) => stream('', 204)), traces);
    final text = traces.first.toString();
    expect(text, 'SseTrace(#${traces.first.streamId} w connect attempt: 1)');
  });

  test(
    'a dropped event and an event that does not decode are traced',
    () async {
      final traces = <SseTrace>[];
      await run(
        FakeTransport(
          (_) => stream('event: ping\ndata: 1\n\nevent: bad\ndata: 2\n\n'),
        ),
        traces,
        reconnect: false,
        decode: (m) => switch (m.event) {
          'ping' => throw const SseEventIgnored(),
          _ => m.data,
        },
      );
      expect(traces.map(describe), [
        'connect 1',
        'open 200',
        'event ping #',
        'event bad #',
        'closed',
      ]);
    },
  );

  test('a failed attempt is an error with its stack trace', () async {
    final traces = <SseTrace>[];
    var calls = 0;
    await run(
      FakeTransport((_) {
        if (calls++ == 0) return stream('');
        if (calls == 2) throw const TransportException(.connection, 'down');
        return stream('', 204);
      }),
      traces,
    );
    expect(traces.map(describe), [
      'connect 1',
      'open 200',
      'reconnecting 1 1s',
      'connect 2',
      'error connection',
      'reconnecting 2 2s',
      'connect 3',
      'open 204',
      'closed',
    ]);
    expect(
      traces.firstWhere((t) => t.kind == SseTraceKind.error).stackTrace,
      isNotNull,
    );
  });

  test(
    'a first connection that fails is traced and returns its error',
    () async {
      final traces = <SseTrace>[];
      final result =
          await ClientSender(
            FakeTransport(
              (_) => throw const TransportException(.connection, 'down'),
            ),
          ).openEvents<String, Never>(
            request,
            (m) => m.data,
            (r) => r.undocumented(),
            call: CallOptions(sse: SseOptions(onTrace: traces.add)),
          );
      expect(result, isA<TransportError<Stream<SseItem<String>>, Never>>());
      expect(traces.map(describe), ['connect 1', 'error connection', 'closed']);
    },
  );

  test('the items are the same with and without a trace', () async {
    String body() => ': a\nid: 1\ndata: x\n\nevent: bad\ndata: y\n\n';
    List<String> names(List<SseItem<String>> items) => [
      for (final i in items) i.toString(),
    ];
    final plain = await run(
      FakeTransport((_) => stream(body(), 204)),
      [],
      reconnect: false,
    );
    final traced = <SseTrace>[];
    final withTrace = await run(
      FakeTransport((_) => stream(body(), 204)),
      traced,
      reconnect: false,
    );
    expect(names(withTrace), names(plain));
    expect(traced, isNotEmpty);
  });

  test(
    'a callback that throws an Exception does not break the stream',
    () async {
      var calls = 0;
      final result =
          await ClientSender(
            FakeTransport((_) => stream('data: x\n\n')),
          ).openEvents<String, Never>(
            request,
            (m) => m.data,
            (r) => r.undocumented(),
            call: CallOptions(
              sse: SseOptions(
                onTrace: (_) {
                  calls++;
                  throw Exception('boom');
                },
              ),
            ),
          );
      final items = await (result as Success<Stream<SseItem<String>>, Never>)
          .data
          .toList();
      expect(items.map((i) => i.runtimeType.toString()), [
        'SseEvent<String>',
        'SseDisconnected<String>',
      ]);
      expect(calls, greaterThan(3));
    },
  );

  test('an idle timeout is an error with a timeout cause', () {
    fakeAsync((async) {
      final traces = <SseTrace>[];
      final transport = ScriptedTransport([ScriptedConnection.open()]);
      ClientSender(transport)
          .openEvents<String, Never>(
            request,
            (m) => m.data,
            (r) => r.undocumented(),
            call: CallOptions(
              sse: SseOptions(
                idleTimeout: const Duration(seconds: 10),
                onTrace: traces.add,
              ),
            ),
          )
          .then((r) {
            (r as Success<Stream<SseItem<String>>, Never>).data.listen((_) {});
          });
      async.elapse(const Duration(seconds: 10));
      expect(traces.map(describe), [
        'connect 1',
        'open 200',
        'error timeout',
        'closed',
      ]);
    });
  });

  test('a cancel is traced and the stream still ends', () {
    fakeAsync((async) {
      final traces = <SseTrace>[];
      final cancel = CancelSignal();
      final items = <SseItem<String>>[];
      ClientSender(ScriptedTransport([ScriptedConnection.open()]))
          .openEvents<String, Never>(
            request,
            (m) => m.data,
            (r) => r.undocumented(),
            call: CallOptions(
              cancel: cancel,
              sse: SseOptions(reconnect: true, onTrace: traces.add),
            ),
          )
          .then((r) {
            (r as Success<Stream<SseItem<String>>, Never>).data.listen(
              items.add,
            );
          });
      async.elapse(const Duration(seconds: 1));
      cancel.cancel('stop');
      async.elapse(const Duration(seconds: 1));
      expect(traces.map(describe), [
        'connect 1',
        'open 200',
        'error cancelled',
        'closed',
      ]);
      expect(items.single, isA<SseDisconnected<String>>());
    });
  });

  test('a listener that cancels closes the trace once', () async {
    final traces = <SseTrace>[];
    final result =
        await ClientSender(
          FakeTransport((_) => stream('data: x\n\n')),
        ).openEvents<String, Never>(
          request,
          (m) => m.data,
          (r) => r.undocumented(),
          call: CallOptions(sse: SseOptions(onTrace: traces.add)),
        );
    final subscription = (result as Success<Stream<SseItem<String>>, Never>)
        .data
        .listen((_) {});
    await subscription.cancel();
    await subscription.cancel();
    expect(traces.where((t) => t.kind == SseTraceKind.closed), hasLength(1));
  });
}
