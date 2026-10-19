import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_adapter.dart';

/// An event-stream response with [text] that then closes.
ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(text))),
  status,
  headers: {
    Headers.contentTypeHeader: ['text/event-stream'],
  },
);

void main() {
  test('an event the decoder ignores is not an item', () async {
    final decoder = SseItemDecoder<String>(
      (m) => m.event == 'ping' ? throw const SseEventIgnored() : m.data,
    );
    final items = await decoder
        .bind(
          Stream.value(
            utf8.encode('data: a\n\nevent: ping\ndata: x\n\ndata: b\n\n'),
          ),
        )
        .toList();
    expect(
      [
        for (final item in items)
          switch (item) {
            SseEvent(:final data) => data,
            SseDisconnected() => 'end',
            _ => '$item',
          },
      ],
      ['a', 'b', 'end'],
    );
  });

  test('the id of an ignored event is the one a reconnection sends', () async {
    var next = 0;
    final adapter = FakeAdapter(
      (_) => [
        _stream('id: 1\ndata: a\n\nid: 2\nevent: ping\ndata: x\n\n'),
        _stream('', 204),
      ][next++],
    );
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents<String, Never>(
          const OperationRequest(
            OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
            streamStatuses: {200, 204},
          ),
          (m) => m.event == 'ping' ? throw const SseEventIgnored() : m.data,
          (r) => r.undocumented(),
          call: CallOptions(
            sse: SseOptions(reconnect: true, wait: (_) async {}),
          ),
        );
    final items = await (result as Success<Stream<SseItem<String>>, Never>).data
        .toList();
    expect(items.whereType<SseEvent<String>>().map((e) => e.data), ['a']);
    expect(items.whereType<SseReconnecting<String>>(), hasLength(1));
    expect(adapter.requests[1].headers['Last-Event-ID'], '2');
  });

  test(
    'the last item carries the id of the last event, also a dropped one',
    () async {
      final items = await SseItemDecoder<String>(
        (m) => throw const SseEventIgnored(),
      ).bind(Stream.value(utf8.encode('id: 9\ndata: x\n\n'))).toList();
      final last = items.single as SseDisconnected<String>;
      expect(last.lastEventId, '9');
    },
  );

  test('it reads as its name', () {
    expect('${const SseEventIgnored()}', 'SseEventIgnored');
  });
}
