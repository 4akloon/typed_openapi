import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'fake_adapter.dart';

/// Opens event streams of a `GET /w` operation, for tests of reconnection.
final class WatchStream {
  /// Opens `watch` through [adapter]; a reconnection waits through nothing
  /// and records its delays in [waits].
  WatchStream(this.adapter, {this.maxAttempts = 5, this.ignorePings = false});

  /// An event-stream response with [text] that then closes.
  static ResponseBody response(String text, [int status = 200]) => ResponseBody(
    Stream.value(Uint8List.fromList(utf8.encode(text))),
    status,
    headers: {
      Headers.contentTypeHeader: ['text/event-stream'],
    },
  );

  /// The adapter every connection goes through.
  final FakeAdapter adapter;

  /// [SseOptions.maxAttempts] of the call.
  final int maxAttempts;

  /// Whether events named `ping` are dropped with `SseEventIgnored`; events
  /// named `bad` never decode.
  final bool ignorePings;

  /// The delays the reconnections waited for.
  final List<Duration> waits = [];

  /// The items of the stream, opened with reconnection on.
  Future<List<SseItem<String>>> items() async {
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents<String, Never>(
          const OperationRequest(
            OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
            streamStatuses: {200, 204},
          ),
          (m) => switch (m.event) {
            'ping' when ignorePings => throw const SseEventIgnored(),
            'bad' => throw JsonDecodeException(
              expected: 'a good event',
              actual: 'a bad one',
            ),
            _ => m.data,
          },
          (r) => r.undocumented(),
          call: CallOptions(
            sse: SseOptions(
              reconnect: true,
              maxAttempts: maxAttempts,
              wait: (delay) async => waits.add(delay),
            ),
          ),
        );
    return (result as Success<Stream<SseItem<String>>, Never>).data.toList();
  }

  /// The `Last-Event-ID` header of each request, null when absent.
  List<Object?> get lastEventIds => [
    for (final request in adapter.requests) request.headers['Last-Event-ID'],
  ];
}
