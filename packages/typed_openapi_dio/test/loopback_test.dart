@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

void main() {
  const chat = OperationInfo(
    operationId: 'chat',
    method: 'POST',
    pathTemplate: '/chat',
  );
  late HttpServer server;
  late Dio dio;
  final bodies = <String>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
    server.listen((request) async {
      bodies.add(await utf8.decodeStream(request));
      // Unbuffered, so each event leaves when it is written.
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response
        ..write('data: one\n\n')
        ..write('data: two\n\n');
      await request.response.flush();
      // The connection stays open until the client cancels.
    });
  });

  tearDown(() => server.close(force: true));

  test(
    'an event stream arrives over a real connection and is cancelled',
    () async {
      final signal = CancelSignal();
      final result = await ClientSender(DioTransport(dio))
          .openEvents<String, Never>(
            const OperationRequest(
              chat,
              body: 'hi',
              contentType: 'text/plain',
              streamStatuses: {200},
            ),
            (message) => message.data,
            (response) => response.undocumented(),
            call: CallOptions(cancel: signal),
          );
      final items = <String>[];
      await for (final item in (result as Success).data as Stream<SseItem>) {
        switch (item) {
          case SseEvent(:final data):
            items.add('$data');
            if (items.length == 2) signal.cancel();
          case SseDisconnected(:final cause):
            items.add('end ${(cause as TransportException?)?.kind.name}');
          default:
            items.add('$item');
        }
      }
      expect(items, ['one', 'two', 'end cancelled']);
      expect(bodies, ['hi']);
    },
  );
}
