import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/watch_opening.dart';

void main() {
  const ok = WatchOpening.stream;
  const status = WatchOpening.status;

  late WatchOpening watch;
  setUp(() => watch = WatchOpening());

  FakeTransport script(List<TransportResponse> answers) {
    var i = 0;
    return FakeTransport((_) => answers[i < answers.length ? i++ : i - 1]);
  }

  Future<List<SseItem<String>>> itemsOf(
    Result<Stream<SseItem<String>>, String> result,
  ) => (result as Success<Stream<SseItem<String>>, String>).data.toList();

  test(
    'retryOpen: false fails fast, an opened stream still reconnects',
    () async {
      final failing = script([status(503)]);
      const off = SseOptions(reconnect: true, retryOpen: false);
      expect(
        await watch.open(failing, sse: off),
        isA<UndocumentedStatus<Object?, Object?>>(),
      );
      expect(failing.requests, hasLength(1));

      final dropping = script([ok('data: a\n\n'), status(404)]);
      final items = await itemsOf(await watch.open(dropping, sse: off));
      expect(items.whereType<SseReconnecting<String>>(), hasLength(1));
    },
  );

  test('retryOpen unset follows reconnect', () async {
    final plain = script([status(503)]);
    await watch.open(plain);
    expect(plain.requests, hasLength(1));

    final reconnecting = script([status(503), ok('data: a\n\n')]);
    await watch.open(reconnecting, sse: const SseOptions(reconnect: true));
    expect(reconnecting.requests, hasLength(2));
  });

  test('retryOpen: true without reconnect retries the opening only', () async {
    final transport = script([status(503), ok('data: a\n\n')]);
    final result = await watch.open(
      transport,
      sse: const SseOptions(retryOpen: true),
    );
    final items = await itemsOf(result);
    expect(transport.requests, hasLength(2));
    expect(items.whereType<SseReconnecting<String>>(), isEmpty);
    expect(items.last, isA<SseDisconnected<String>>());
  });

  test('SseReconnection.off is never retried, even with retryOpen', () async {
    final transport = script([status(503)]);
    final result = await watch.open(
      transport,
      sse: const SseOptions(reconnect: true, retryOpen: true),
      reconnection: SseReconnection.off,
    );
    expect(result, isA<UndocumentedStatus<Object?, Object?>>());
    expect(transport.requests, hasLength(1));
  });

  group('a FileUpload.stream body', () {
    // Fresh per test: the fake transport reads the stream.
    OperationRequest post() => OperationRequest(
      const OperationInfo(
        operationId: 'w',
        method: 'POST',
        pathTemplate: '/w',
      ),
      streamStatuses: const {200, 204},
      body: FileUpload.stream(Stream.value(Uint8List(1)), length: 1),
      contentType: 'application/octet-stream',
    );

    test('is never sent twice when the opening fails', () async {
      final transport = script([status(503)]);
      final result = await watch.open(
        transport,
        sse: const SseOptions(reconnect: true),
        reconnection: SseReconnection.on,
        request: post(),
      );
      expect(result, isA<UndocumentedStatus<Object?, Object?>>());
      expect(transport.requests, hasLength(1));
    });

    test('is never sent twice when the stream closes', () async {
      final transport = script([ok('data: a\n\n')]);
      final result = await watch.open(
        transport,
        sse: const SseOptions(reconnect: true),
        reconnection: SseReconnection.on,
        request: post(),
      );
      final items = await itemsOf(result);
      expect(items.whereType<SseReconnecting<String>>(), isEmpty);
      expect(items.last, isA<SseDisconnected<String>>());
      expect(transport.requests, hasLength(1));
    });
  });

  group('retryWhen', () {
    test('replaces the default', () async {
      final transport = script([status(404), ok('data: a\n\n')]);
      final result = await watch.open(
        transport,
        sse: SseOptions(
          reconnect: true,
          retryWhen: (f) => f is UndocumentedStatus && f.statusCode == 404,
        ),
      );
      expect(result, isA<Success<Object?, Object?>>());
      expect(transport.requests, hasLength(2));

      final final503 = script([status(503)]);
      final failed = await watch.open(
        final503,
        sse: SseOptions(reconnect: true, retryWhen: (_) => false),
      );
      expect(failed, isA<UndocumentedStatus<Object?, Object?>>());
      expect(final503.requests, hasLength(1));
    });

    test('an Exception counts as final', () async {
      final transport = script([status(503)]);
      final result = await watch.open(
        transport,
        sse: SseOptions(
          reconnect: true,
          retryWhen: (_) => throw const FormatException('x'),
        ),
      );
      expect(result, isA<UndocumentedStatus<Object?, Object?>>());
      expect(transport.requests, hasLength(1));
    });

    test('an Error completes the Future with it', () async {
      final transport = script([status(503)]);
      await expectLater(
        watch.open(
          transport,
          sse: SseOptions(
            reconnect: true,
            retryWhen: (_) => throw StateError('bug'),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('is never asked about a cancel', () async {
      final cancel = CancelSignal();
      var asked = 0;
      final transport = script([status(503)]);
      final pending = watch.open(
        transport,
        cancel: cancel,
        sse: SseOptions(
          reconnect: true,
          // The wait is held until the cancel arrives.
          wait: (_) => Completer<void>().future,
          retryWhen: (_) {
            asked++;
            return true;
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      expect(await pending, isA<Cancelled<Object?, Object?>>());
      expect(asked, 1);
      expect(transport.requests, hasLength(1));
    });
  });

  test(
    'an Exception thrown by wait ends the opening with the last failure',
    () async {
      final transport = script([status(503), ok('data: a\n\n')]);
      final result = await watch.open(
        transport,
        sse: SseOptions(
          reconnect: true,
          wait: (_) => Future.error(const FormatException('x')),
        ),
      );
      expect(result, isA<UndocumentedStatus<Object?, Object?>>());
      expect(transport.requests, hasLength(1));
    },
  );

  test('a wait that throws an Exception at once ends the opening', () async {
    final transport = script([status(503), ok('data: a\n\n')]);
    final result = await runZonedGuarded(
      () => watch.open(
        transport,
        sse: SseOptions(
          reconnect: true,
          wait: (_) => throw const FormatException('x'),
        ),
      ),
      (error, _) => fail('escaped to the zone: $error'),
    );
    expect(result, isA<UndocumentedStatus<Object?, Object?>>());
    expect(transport.requests, hasLength(1));
  });

  test('a wait that throws an Error at once completes the Future', () async {
    final transport = script([status(503)]);
    await expectLater(
      watch.open(
        transport,
        sse: SseOptions(
          reconnect: true,
          wait: (_) => throw StateError('bug'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a wait that throws an Error at once is the single error of a '
      'reconnecting stream', () async {
    final transport = script([ok('data: a\n\n')]);
    final result = await watch.open(
      transport,
      sse: SseOptions(
        reconnect: true,
        wait: (_) => throw StateError('bug'),
      ),
    );
    final errors = <Object>[];
    await (result as Success<Stream<SseItem<String>>, String>).data
        .handleError(errors.add)
        .toList();
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
  });
}
