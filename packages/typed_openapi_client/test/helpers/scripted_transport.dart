import 'dart:async';
import 'dart:convert';

import 'package:typed_openapi_client/typed_openapi_client.dart';

/// One connection a [ScriptedTransport] answers: the test writes its body
/// and closes it, or never answers the headers.
final class ScriptedConnection {
  /// A connection whose headers arrive at once; the body is [body].
  ScriptedConnection.open({int status = 200})
    : _status = status,
      _headers = null;

  /// A connection whose headers never arrive.
  ScriptedConnection.hanging() : _status = 0, _headers = Completer();

  final int _status;
  final Completer<TransportResponse>? _headers;

  /// The body of the response; the test adds chunks and closes it.
  final StreamController<List<int>> body = StreamController<List<int>>();

  /// Writes [text] to the body.
  void write(String text) => body.add(utf8.encode(text));

  Future<TransportResponse> _response(CancelSignal? cancel) {
    final pending = _headers;
    if (pending != null) return pending.future;
    return Future.value(
      TransportResponse(
        statusCode: _status,
        headers: const {
          'content-type': ['text/event-stream'],
        },
        body: _abortable(cancel),
      ),
    );
  }

  /// The body, which fails with a cancelled [TransportException] when
  /// [cancel] fires, as a real transport aborts the connection. Unlike
  /// `FakeTransport.cancellable` it never cancels a subscription twice:
  /// under `fakeAsync` the future of a second cancel completes outside the
  /// fake zone, and a `cancelOnError` listener would wait for it.
  Stream<List<int>> _abortable(CancelSignal? cancel) {
    final out = StreamController<List<int>>();
    StreamSubscription<List<int>>? source;
    var isOver = false;
    out
      ..onListen = () {
        source = body.stream.listen(
          out.add,
          onError: out.addError,
          onDone: () {
            isOver = true;
            out.close();
          },
        );
        cancel?.whenCancelled.then((_) {
          if (isOver) return;
          isOver = true;
          source?.cancel();
          out
            ..addError(const TransportException(.cancelled, 'cancelled'))
            ..close();
        });
      }
      ..onPause = (() => source?.pause())
      ..onResume = (() => source?.resume())
      ..onCancel = () {
        if (isOver) return null;
        isOver = true;
        return source?.cancel();
      };
    return out.stream;
  }
}

/// A transport whose connections the test drives: the n-th request is
/// answered by the n-th [connections] entry.
final class ScriptedTransport implements ClientTransport {
  /// Answers requests from [connections] in order.
  ScriptedTransport(this.connections);

  /// The connections, in the order the requests come.
  final List<ScriptedConnection> connections;

  /// The requests seen.
  final List<TransportRequest> requests = [];

  /// Per request, whether its cancel signal fired.
  final List<bool> cancelsFired = [];

  @override
  Future<TransportResponse> send(TransportRequest request) {
    final index = requests.length;
    requests.add(request);
    cancelsFired.add(false);
    request.cancel?.whenCancelled.then((_) => cancelsFired[index] = true);
    return connections[index]._response(request.cancel);
  }
}
