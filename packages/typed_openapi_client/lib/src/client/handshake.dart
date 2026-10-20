import 'dart:async';

import '../transport/cancel_signal.dart';
import '../transport/client_transport.dart';
import '../transport/transport_exception.dart';
import '../transport/transport_request.dart';
import '../transport/transport_response.dart';

/// Bounds the wait for the response headers of one connection attempt
/// (`SseOptions.handshakeTimeout`).
final class Handshake {
  /// Creates the bound; a null [timeout] waits as long as the transport
  /// does.
  const Handshake(this.timeout);

  /// How long the headers may take, or null for no bound.
  final Duration? timeout;

  /// Sends [request] through [transport]. When the headers do not arrive in
  /// time, [signal] is cancelled, so the transport aborts the request, and
  /// the call throws a [TransportException] of kind timeout.
  Future<TransportResponse> send(
    ClientTransport transport,
    TransportRequest request,
    CancelSignal signal,
  ) {
    final sent = transport.send(request);
    final limit = timeout;
    if (limit == null) return sent;
    return sent.timeout(
      limit,
      onTimeout: () {
        signal.cancel('the event stream did not answer in time');
        throw TransportException(
          .timeout,
          'No response headers arrived within $limit.',
        );
      },
    );
  }
}
