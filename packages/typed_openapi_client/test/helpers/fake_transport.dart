import 'dart:async';
import 'dart:convert';

import 'package:typed_openapi_client/typed_openapi_client.dart';

/// A transport that answers from memory, so tests never touch the network.
/// It records every request with its body text.
final class FakeTransport implements ClientTransport {
  /// Answers every request with [respond].
  FakeTransport(this.respond);

  /// A JSON response with [status].
  factory FakeTransport.json(int status, Object? body) => FakeTransport(
    (_) => response(jsonEncode(body), status, 'application/json'),
  );

  /// A response with [status], [text] and [contentType].
  factory FakeTransport.text(int status, String text, String contentType) =>
      FakeTransport((_) => response(text, status, contentType));

  /// A response with [status] whose body is [text] in UTF-8, of
  /// [contentType] when it is given.
  static TransportResponse response(
    String text,
    int status, [
    String? contentType,
  ]) => TransportResponse(
    statusCode: status,
    body: Stream.value(utf8.encode(text)),
    headers: {
      'content-type': ?(contentType == null ? null : [contentType]),
    },
  );

  /// The value of the header [name] of [request] (any case), its values
  /// joined with `, `; null when the request has none.
  static String? header(TransportRequest request, String name) {
    for (final MapEntry(:key, :value) in request.headers.entries) {
      if (key.toLowerCase() == name.toLowerCase()) return value.join(', ');
    }
    return null;
  }

  /// Builds the response, or throws a [TransportException].
  final TransportResponse Function(TransportRequest request) respond;

  /// The requests seen, in order.
  final List<TransportRequest> requests = [];

  /// The request bodies seen, as text.
  final List<String> bodies = [];

  /// Per request, whether its cancel signal fired: the request was
  /// cancelled and a real transport would close the connection.
  final List<bool> cancelsFired = [];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    final index = cancelsFired.length;
    cancelsFired.add(false);
    request.cancel?.whenCancelled.then((_) => cancelsFired[index] = true);
    final bytes = <int>[];
    if (request.body case final body?) {
      await for (final chunk in body) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes, allowMalformed: true));
    return cancellable(respond(request), request.cancel);
  }

  /// [response] whose body fails with a [TransportException] of kind
  /// cancelled when [cancel] fires before it ends, as a real transport
  /// aborts the connection.
  static TransportResponse cancellable(
    TransportResponse response,
    CancelSignal? cancel,
  ) {
    if (cancel == null) return response;
    final body = StreamController<List<int>>(sync: true);
    StreamSubscription<List<int>>? source;
    body
      ..onListen = () {
        source = response.body.listen(
          body.add,
          onError: body.addError,
          onDone: body.close,
        );
        cancel.whenCancelled.then((_) {
          if (body.isClosed) return;
          source?.cancel();
          body
            ..addError(const TransportException(.cancelled, 'cancelled'))
            ..close();
        });
      }
      ..onPause = (() => source?.pause())
      ..onResume = (() => source?.resume())
      ..onCancel = (() => source?.cancel());
    return TransportResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body.stream,
    );
  }
}
