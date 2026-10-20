import 'dart:async';
import 'dart:convert';

import 'package:typed_openapi_client/typed_openapi_client.dart';

/// Opens event streams of a `GET /w` operation, for tests of the retried
/// opening. An instance records the delays of its injected `wait`.
final class WatchOpening {
  /// The delays the retries waited for.
  final List<Duration> waits = [];

  /// An error response with [code], lower-cased [headers] and [body].
  static TransportResponse status(
    int code, {
    Map<String, String> headers = const {},
    String body = '',
  }) => TransportResponse(
    statusCode: code,
    body: _replayable(body),
    headers: {
      for (final MapEntry(:key, :value) in headers.entries)
        key.toLowerCase(): [value],
    },
  );

  /// A 200 event stream with [text] that then closes.
  static TransportResponse stream(String text) => TransportResponse(
    statusCode: 200,
    body: _replayable(text),
    headers: const {
      'content-type': ['text/event-stream'],
    },
  );

  // A stream that every listener gets whole, so a script can answer with one
  // response more than once.
  static Stream<List<int>> _replayable(String text) => Stream.multi((out) {
    if (text.isNotEmpty) out.add(utf8.encode(text));
    out.close();
  });

  /// The `GET /w` operation of the tests.
  static const OperationRequest get = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  /// Opens the operation over [transport]. [sse] gets a `wait` that records
  /// its delays in [waits] unless it sets one.
  Future<Result<Stream<SseItem<String>>, String>> open(
    ClientTransport transport, {
    SseOptions? sse,
    SseReconnection reconnection = .onRequest,
    OperationRequest? request,
    CancelSignal? cancel,
    Map<String, Object?> headers = const {},
  }) {
    final options = sse ?? const SseOptions();
    return ClientSender(transport).openEvents<String, String>(
      request ?? get,
      (m) => m.data,
      (r) => r.undocumented(),
      call: CallOptions(
        cancel: cancel,
        headers: headers,
        sse: SseOptions(wait: (d) async => waits.add(d)).merge(options),
      ),
      reconnection: reconnection,
    );
  }
}
