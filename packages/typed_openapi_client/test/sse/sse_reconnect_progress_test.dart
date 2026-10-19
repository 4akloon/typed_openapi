import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/watch_stream.dart';

void main() {
  /// A stream whose connections answer [bodies] in order, then 204.
  WatchStream watch(List<String> bodies, {int maxAttempts = 5}) {
    var next = 0;
    return WatchStream(
      FakeTransport(
        (_) => next < bodies.length
            ? WatchStream.response(bodies[next++])
            : WatchStream.response('', 204),
      ),
      maxAttempts: maxAttempts,
      ignorePings: true,
    );
  }

  const ping = 'id: 1\nevent: ping\ndata: x\n\n';

  test('connections that deliver only ignored events keep reconnecting '
      'with the first delay', () async {
    final stream = watch([for (var i = 0; i < 6; i++) ping], maxAttempts: 2);
    final items = await stream.items();
    expect(stream.waits, everyElement(const Duration(seconds: 1)));
    expect(stream.waits, hasLength(6));
    expect(items.last, isA<SseDisconnected<String>>());
    expect(stream.adapter.requests, hasLength(7));
  });

  test('connections that deliver nothing still count as failed', () async {
    final stream = watch([
      for (var i = 0; i < 6; i++) ': hi\n\n',
    ], maxAttempts: 2);
    await stream.items();
    expect(stream.waits, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ]);
  });

  test('a connection with a decode error resets the count too', () async {
    final stream = watch([
      for (var i = 0; i < 6; i++) 'event: bad\ndata: x\n\n',
    ], maxAttempts: 2);
    await stream.items();
    expect(stream.waits, everyElement(const Duration(seconds: 1)));
    expect(stream.waits, hasLength(6));
  });

  group('SseDisconnected.receivedMessage', () {
    Future<SseDisconnected<String>> last(String text) async {
      final items = await SseItemDecoder<String>(
        (m) => m.event == 'ping' ? throw const SseEventIgnored() : m.data,
      ).bind(Stream.value(text.codeUnits)).toList();
      return items.last as SseDisconnected<String>;
    }

    test('is true after an event the decoder dropped', () async {
      expect((await last(ping)).receivedMessage, isTrue);
    });

    test('is false after only comments', () async {
      expect((await last(': hi\n\n')).receivedMessage, isFalse);
    });
  });
}
