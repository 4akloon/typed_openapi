import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

/// A [Random] that answers [values] in order, then the last one.
final class _Fixed implements Random {
  _Fixed(this.values);

  final List<double> values;
  int _next = 0;

  @override
  double nextDouble() => values[_next < values.length - 1 ? _next++ : _next];

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

void main() {
  const request = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  /// Opens a stream whose first connection closes at once and whose
  /// [refused] reconnections fail, then one brings an event and the next
  /// ends it with a 204. Returns the items and the waited delays.
  Future<(List<SseItem<String>>, List<Duration>)> run(
    SseOptions Function(Future<void> Function(Duration)) options, {
    required int refused,
    String first = '',
  }) async {
    final waits = <Duration>[];
    var calls = 0;
    final transport = FakeTransport((_) {
      final n = calls++;
      if (n == 0) {
        return FakeTransport.response(first, 200, 'text/event-stream');
      }
      if (n <= refused) {
        throw const TransportException(.connection, 'refused');
      }
      return FakeTransport.response('', 204, 'text/event-stream');
    });
    final result = await ClientSender(transport).openEvents<String, Never>(
      request,
      (m) => m.data,
      (r) => r.undocumented(),
      call: CallOptions(sse: options((d) async => waits.add(d))),
    );
    final stream = (result as Success<Stream<SseItem<String>>, Never>).data;
    return (await stream.toList(), waits);
  }

  List<int> attempts(List<SseItem<String>> items) => [
    for (final item in items)
      if (item is SseReconnecting<String>) item.attempt,
  ];

  group('maxAttempts', () {
    test('null never gives up', () async {
      final (items, waits) = await run(
        (wait) => SseOptions(reconnect: true, maxAttempts: null, wait: wait),
        refused: 40,
      );
      expect(waits, hasLength(41));
      expect(attempts(items).last, 41);
      expect(items.last, isA<SseDisconnected<String>>());
      expect((items.last as SseDisconnected).cause, isNull);
    });

    test('a number still ends the stream', () async {
      final (items, _) = await run(
        (wait) => SseOptions(reconnect: true, maxAttempts: 3, wait: wait),
        refused: 40,
      );
      expect(attempts(items), [1, 2, 3]);
      expect(
        (items.last as SseDisconnected).cause,
        isA<TransportException>(),
      );
    });
  });

  group('cooldown', () {
    SseOptions Function(Future<void> Function(Duration)) cooldown({
      int? maxAttempts,
    }) =>
        (wait) => SseOptions(
          reconnect: true,
          maxAttempts: maxAttempts,
          cooldown: const SseCooldown(
            after: 3,
            duration: Duration(minutes: 5),
          ),
          wait: wait,
        );

    test('pauses after N failed attempts and restarts the backoff', () async {
      final (items, waits) = await run(cooldown(), refused: 8);
      expect(
        [for (final d in waits) d.inSeconds],
        [1, 2, 4, 300, 1, 2, 4, 300, 1],
      );
      expect(attempts(items), [1, 2, 3, 4, 1, 2, 3, 4, 1]);
    });

    test('a message resets the count before the cooldown', () async {
      final (_, waits) = await run(
        cooldown(),
        refused: 2,
        first: 'data: a\n\n',
      );
      expect([for (final d in waits) d.inSeconds], [1, 2, 4]);
    });

    test('maxAttempts below the cooldown ends the stream first', () async {
      final (items, waits) = await run(cooldown(maxAttempts: 2), refused: 8);
      expect([for (final d in waits) d.inSeconds], [1, 2]);
      expect(items.last, isA<SseDisconnected<String>>());
    });
  });

  group('jitter', () {
    SseOptions Function(Future<void> Function(Duration)) jittered(
      Random random,
    ) =>
        (wait) => SseOptions(
          reconnect: true,
          jitter: 0.2,
          random: random,
          wait: wait,
        );

    test('moves each delay within the ratio, either way', () async {
      final (_, waits) = await run(
        jittered(_Fixed([0, 1, 0.5])),
        refused: 2,
      );
      expect(waits, [
        const Duration(milliseconds: 800),
        const Duration(milliseconds: 2400),
        const Duration(seconds: 4),
      ]);
    });

    test('stays in bounds for a seeded random source', () async {
      final (_, waits) = await run(jittered(Random(7)), refused: 5);
      for (var i = 0; i < waits.length; i++) {
        final base = [1, 2, 4, 8, 16, 30][i] * 1000;
        expect(
          waits[i].inMilliseconds,
          inInclusiveRange(base * 0.8, base * 1.2),
        );
      }
      expect(waits.toSet(), hasLength(waits.length));
    });

    test('is the same with the same seed', () async {
      final a = await run(jittered(Random(3)), refused: 4);
      final b = await run(jittered(Random(3)), refused: 4);
      expect(a.$2, b.$2);
    });

    test('does not move a delay the server asked for', () async {
      final (_, waits) = await run(
        jittered(_Fixed([0])),
        refused: 1,
        first: 'retry: 2000\n\n',
      );
      expect(waits.first, const Duration(seconds: 2));
    });

    test('does not move the cooldown', () async {
      final (_, waits) = await run(
        (wait) => SseOptions(
          reconnect: true,
          jitter: 0.2,
          random: _Fixed([1]),
          cooldown: const SseCooldown(after: 1, duration: Duration(minutes: 1)),
          wait: wait,
        ),
        refused: 1,
      );
      expect(waits.last, const Duration(minutes: 1));
    });
  });
}
