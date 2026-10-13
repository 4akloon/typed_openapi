import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';

/// An event-stream response with [text] that then closes.
ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(text))),
  status,
  headers: {
    Headers.contentTypeHeader: ['text/event-stream'],
  },
);

/// A connection that fails before any response.
ResponseBody _refused(RequestOptions options) => throw DioException(
  requestOptions: options,
  type: DioExceptionType.connectionError,
  message: 'refused',
);

/// Answers the requests in order with [answers]; the last one repeats.
FakeAdapter _adapter(List<ResponseBody Function(RequestOptions)> answers) {
  var next = 0;
  return FakeAdapter(
    (options) => answers[next < answers.length - 1 ? next++ : next](options),
  );
}

void main() {
  const watch = OperationRequest(
    OperationInfo(operationId: 'watch', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  Result<Stream<SseItem<String>>, String> decodeError(RawResponse r) =>
      switch (r.statusCode) {
        404 => r.error(r.text),
        _ => r.undocumented(),
      };

  String describe(SseItem<String> item) => switch (item) {
    SseEvent(:final data, :final id) => 'event $data #$id',
    SseDecodeError() => 'decode error',
    SseReconnecting(:final attempt, :final delay) =>
      'reconnecting $attempt after ${delay.inMilliseconds}ms',
    SseDisconnected(cause: DioException(:final type)) => 'end ${type.name}',
    SseDisconnected(cause: HttpError(:final statusCode)) =>
      'end http $statusCode',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  /// The items of a [watch] stream opened through [adapter].
  Future<List<String>> items(
    FakeAdapter adapter, {
    SseReconnection reconnection = SseReconnection.onRequest,
    SseOptions? sse,
    List<Duration>? waits,
  }) async {
    final options = SseOptions(
      reconnect: sse?.reconnect,
      delay: sse?.delay ?? const Duration(seconds: 1),
      maxAttempts: sse?.maxAttempts ?? 5,
      maxDelay: sse?.maxDelay ?? const Duration(seconds: 30),
      wait: (delay) async => waits?.add(delay),
    );
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents(
          watch,
          (m) => m.data,
          decodeError,
          call: CallOptions(sse: options),
          reconnection: reconnection,
        );
    final stream = (result as Success<Stream<SseItem<String>>, String>).data;
    return (await stream.toList()).map(describe).toList();
  }

  group('delays', () {
    test('double from 1 s up to 30 s without a server retry', () {
      const options = SseOptions();
      expect(
        [for (var i = 1; i <= 7; i++) options.delayBefore(i, null)],
        [
          for (final s in [1, 2, 4, 8, 16, 30, 30]) Duration(seconds: s),
        ],
      );
    });

    test('start from the server retry', () {
      const options = SseOptions();
      const retry = Duration(milliseconds: 2500);
      expect(options.delayBefore(1, retry), retry);
      expect(options.delayBefore(2, retry), const Duration(seconds: 5));
      expect(options.delayBefore(5, retry), const Duration(seconds: 30));
    });

    test('a server retry over the cap is kept as it is', () {
      const options = SseOptions();
      const retry = Duration(minutes: 2);
      expect(options.delayBefore(3, retry), retry);
    });
  });

  test('a GET reconnects only when the call asks, a POST never', () {
    const asks = SseOptions(reconnect: true);
    const refuses = SseOptions(reconnect: false);
    const none = SseOptions();
    expect(
      [
        for (final policy in SseReconnection.values)
          [
            for (final options in [none, asks, refuses])
              policy.reconnects(options),
          ],
      ],
      [
        [false, false, false],
        [false, true, false],
        [true, true, false],
      ],
    );
  });

  test('without reconnection the stream ends when the server closes', () async {
    final adapter = _adapter([(_) => _stream('data: a\n\n')]);
    expect(await items(adapter), ['event a #', 'end closed']);
    expect(adapter.requests, hasLength(1));
  });

  test('a reconnect sends Last-Event-ID and waits the server retry', () async {
    final waits = <Duration>[];
    final adapter = _adapter([
      (_) => _stream('retry: 2500\nid: 7\ndata: a\n\n'),
      (_) => _stream('data: b\n\n', 204),
    ]);
    expect(
      await items(
        adapter,
        sse: const SseOptions(reconnect: true),
        waits: waits,
      ),
      ['event a #7', 'reconnecting 1 after 2500ms', 'end closed'],
    );
    expect(waits, [const Duration(milliseconds: 2500)]);
    expect(adapter.requests[0].headers['Last-Event-ID'], isNull);
    expect(adapter.requests[1].headers['Last-Event-ID'], '7');
  });

  test('the event id carries over to the next connection', () async {
    final adapter = _adapter([
      (_) => _stream('id: 7\ndata: a\n\n'),
      (_) => _stream('data: b\n\n'),
      (_) => _stream('', 204),
    ]);
    expect(
      await items(adapter, reconnection: SseReconnection.on),
      [
        'event a #7',
        'reconnecting 1 after 1000ms',
        'event b #7',
        'reconnecting 1 after 1000ms',
        'end closed',
      ],
    );
    expect(adapter.requests[2].headers['Last-Event-ID'], '7');
  });

  test(
    'failed attempts back off up to the cap and stop at the limit',
    () async {
      final waits = <Duration>[];
      final adapter = _adapter([(_) => _stream('data: a\n\n'), _refused]);
      expect(
        await items(
          adapter,
          sse: const SseOptions(
            reconnect: true,
            maxAttempts: 4,
            maxDelay: Duration(seconds: 3),
          ),
          waits: waits,
        ),
        [
          'event a #',
          'reconnecting 1 after 1000ms',
          'reconnecting 2 after 2000ms',
          'reconnecting 3 after 3000ms',
          'reconnecting 4 after 3000ms',
          'end connectionError',
        ],
      );
      expect(adapter.requests, hasLength(5));
    },
  );

  test('a POST does not reconnect even when the call asks', () async {
    final adapter = _adapter([(_) => _stream('data: a\n\n')]);
    expect(
      await items(
        adapter,
        reconnection: SseReconnection.off,
        sse: const SseOptions(reconnect: true),
      ),
      ['event a #', 'end closed'],
    );
  });

  test('an attempt answered with an error status ends the stream', () async {
    final adapter = _adapter([
      (_) => _stream('data: a\n\n'),
      (_) => ResponseBody.fromString('gone', 404),
    ]);
    expect(await items(adapter, reconnection: SseReconnection.on), [
      'event a #',
      'reconnecting 1 after 1000ms',
      'end http 404',
    ]);
  });

  test(
    'cancelling during the wait ends the stream, no request follows',
    () async {
      final token = CancelToken();
      final adapter = _adapter([(_) => _stream('data: a\n\n')]);
      final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
          .openEvents(
            watch,
            (m) => m.data,
            decodeError,
            call: CallOptions(
              cancelToken: token,
              sse: SseOptions(
                reconnect: true,
                wait: (_) => Completer<void>().future,
              ),
            ),
          );
      final stream = (result as Success<Stream<SseItem<String>>, String>).data;
      final seen = <String>[];
      final done = Completer<void>();
      stream.listen((item) {
        seen.add(describe(item));
        if (item is SseReconnecting) token.cancel();
      }, onDone: done.complete);
      await done.future;
      expect(seen, ['event a #', 'reconnecting 1 after 1000ms', 'end cancel']);
      expect(adapter.requests, hasLength(1));
    },
  );

  test('a listener that cancels during the wait stops the attempts', () async {
    final wait = Completer<void>();
    final adapter = _adapter([(_) => _stream('data: a\n\n')]);
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents(
          watch,
          (m) => m.data,
          decodeError,
          call: CallOptions(
            sse: SseOptions(reconnect: true, wait: (_) => wait.future),
          ),
        );
    final stream = (result as Success<Stream<SseItem<String>>, String>).data;
    late final StreamSubscription<SseItem<String>> subscription;
    subscription = stream.listen((item) {
      if (item is SseReconnecting) subscription.cancel();
    });
    await pumpEventQueue();
    wait.complete();
    await pumpEventQueue();
    expect(adapter.requests, hasLength(1));
  });

  test('cancelling during the stream ends it without a reconnect', () async {
    final token = CancelToken();
    final body = StreamController<Uint8List>();
    addTearDown(body.close);
    final adapter = _adapter([
      (_) => ResponseBody(
        body.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      ),
    ]);
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents(
          watch,
          (m) => m.data,
          decodeError,
          call: CallOptions(cancelToken: token),
          reconnection: SseReconnection.on,
        );
    final stream = (result as Success<Stream<SseItem<String>>, String>).data;
    final seen = <String>[];
    final done = Completer<void>();
    stream.listen((item) {
      seen.add(describe(item));
      if (item is SseEvent) token.cancel();
    }, onDone: done.complete);
    body.add(Uint8List.fromList(utf8.encode('data: a\n\n')));
    await done.future;
    expect(seen, ['event a #', 'end cancel']);
    expect(adapter.requests, hasLength(1));
  });
}
