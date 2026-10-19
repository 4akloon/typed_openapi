import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

/// An event-stream response with [text] that then closes.
TransportResponse _stream(String text, [int status = 200]) =>
    FakeTransport.response(text, status, 'text/event-stream');

void main() {
  const watch = OperationRequest(
    OperationInfo(operationId: 'watch', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  Result<Stream<SseItem<String>>, String> decodeError(RawResponse r) =>
      r.undocumented();

  /// The `Last-Event-ID` of each request of a [watch] stream whose
  /// connections answer with [bodies] (then 204), for the user's [headers].
  Future<List<Object?>> sent(
    List<String> bodies,
    Map<String, Object?> headers,
  ) async {
    var next = 0;
    final adapter = FakeTransport(
      (_) => next < bodies.length ? _stream(bodies[next++]) : _stream('', 204),
    );
    final result = await ClientSender(adapter).openEvents(
      watch,
      (m) => m.data,
      decodeError,
      call: CallOptions(
        headers: headers,
        sse: SseOptions(reconnect: true, wait: (_) async {}),
      ),
    );
    await (result as Success<Stream<SseItem<String>>, String>).data
        .drain<void>();
    return [
      for (final request in adapter.requests)
        FakeTransport.header(request, 'Last-Event-ID') ??
            FakeTransport.header(request, 'last-event-id'),
    ];
  }

  group('a Last-Event-ID the user sets', () {
    test('goes with every request until an event id replaces it', () async {
      expect(await sent(['data: a\n\n'], {'Last-Event-ID': 'u'}), ['u', 'u']);
    });

    test('is replaced by the id of an event on a reconnection', () async {
      expect(
        await sent(['id: 5\ndata: a\n\n'], {'Last-Event-ID': 'u'}),
        ['u', '5'],
      );
    });

    test('is not sent again after the stream resets its id', () async {
      expect(
        await sent(
          ['id: 5\ndata: a\n\n', 'id:\ndata: b\n\n'],
          {
            'Last-Event-ID': 'u',
          },
        ),
        ['u', '5', null],
      );
    });

    test('is found in any case and not sent twice', () async {
      expect(
        await sent(['id: 7\ndata: a\n\n'], {'last-event-id': 'u'}),
        ['u', '7'],
      );
    });

    test('stays in the map the user passed', () async {
      final headers = <String, Object?>{'Last-Event-ID': 'u'};
      await sent(['id: 5\ndata: a\n\n'], headers);
      expect(headers, {'Last-Event-ID': 'u'});
    });
  });
}
