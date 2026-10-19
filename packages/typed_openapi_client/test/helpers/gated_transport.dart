import 'dart:async';

import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'fake_transport.dart';

/// A transport whose answers a test can hold back: [respond] is called
/// with the request and its index and may wait on a gate. It tells when a
/// request started and whether it was cancelled, and a cancel before the
/// answer fails the request as a real transport does.
final class GatedTransport implements ClientTransport {
  /// Answers the request number `index` with the future [respond] returns.
  GatedTransport(this.respond);

  /// Builds the response of a request, possibly later.
  final Future<TransportResponse> Function(TransportRequest request, int index)
  respond;

  /// The requests seen, in order.
  final List<TransportRequest> requests = [];

  /// Per request, whether its cancel signal fired.
  final List<bool> cancelsFired = [];

  final Map<int, Completer<void>> _started = {};

  /// Completes when the request number [index] reaches the transport.
  Future<void> started(int index) =>
      (_started[index] ??= Completer<void>()).future;

  @override
  Future<TransportResponse> send(TransportRequest request) {
    final index = requests.length;
    requests.add(request);
    cancelsFired.add(false);
    final started = _started[index] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    final answer = respond(
      request,
      index,
    ).then((r) => FakeTransport.cancellable(r, request.cancel));
    final cancel = request.cancel;
    if (cancel == null) return answer;
    final cancelled = cancel.whenCancelled.then<TransportResponse>((_) {
      cancelsFired[index] = true;
      throw TransportException(.cancelled, 'cancelled: ${cancel.reason}');
    });
    return Future.any([answer, cancelled]);
  }
}
