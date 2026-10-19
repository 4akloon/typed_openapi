import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/watch_stream.dart';

void main() {
  /// The last item of [text] decoded by an `SseItemDecoder`.
  Future<SseDisconnected<String>> last(String text) async {
    final items = await SseItemDecoder<String>(
      (m) => m.data,
    ).bind(Stream.value(text.codeUnits)).toList();
    return items.last as SseDisconnected<String>;
  }

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
    );
  }

  group('a block without data', () {
    test('sets the last event id of the stream', () async {
      expect((await last('id: 9\n\n')).lastEventId, '9');
    });

    test('with an empty id resets the last event id', () async {
      expect((await last('id: 4\n\nid\n\n')).lastEventId, '');
    });

    test('sets the reconnection time', () async {
      expect(
        (await last('retry: 3000\n\n')).retry,
        const Duration(seconds: 3),
      );
    });

    test('is no message for SseDecoder', () async {
      final messages = await const SseDecoder()
          .bind(Stream.value('id: 9\n\n'.codeUnits))
          .toList();
      expect(messages, isEmpty);
    });

    test('is no message', () async {
      expect((await last('id: 9\n\n')).receivedMessage, isFalse);
    });

    test('is sent as Last-Event-ID by the next connection', () async {
      final stream = watch(['id: 9\n\n']);
      await stream.items();
      expect(stream.lastEventIds, [null, '9']);
    });

    test('has its retry as the delay before the next connection', () async {
      final stream = watch(['retry: 3000\n\n']);
      await stream.items();
      expect(stream.waits, [const Duration(seconds: 3)]);
    });

    test('is dropped when the stream ends before its empty line', () async {
      expect((await last('id: 5\n')).lastEventId, '');
    });
  });

  group('SseDisconnected.lastEventId', () {
    test('is the empty string when the stream had no id', () async {
      expect((await last('data: a\n\n')).lastEventId, '');
      expect(const SseDisconnected<String>().lastEventId, '');
    });

    test('of a stream that gave up is the last id it saw', () async {
      final stream = watch([
        for (var i = 0; i < 6; i++) 'id: 9\n\n',
      ], maxAttempts: 2);
      final items = await stream.items();
      expect((items.last as SseDisconnected<String>).lastEventId, '9');
    });

    test('of a stream the server ended with 204 is the last id', () async {
      final stream = watch(['id: 9\n\n']);
      final items = await stream.items();
      expect((items.last as SseDisconnected<String>).lastEventId, '9');
    });
  });
}
