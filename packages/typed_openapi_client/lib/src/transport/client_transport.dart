import 'transport_request.dart';
import 'transport_response.dart';

/// Sends finished HTTP requests: the one thing a generated client needs
/// from an HTTP stack.
///
/// The client core builds the request (URL, headers, body bytes), reads the
/// response and maps it to a `Result`, so every transport behaves the same
/// on the wire. A transport owns what its HTTP stack owns: the base URL it
/// resolves [TransportRequest.target] against, timeouts, retries, redirects,
/// proxies, certificates, cookies and authorization. `typed_openapi_dio`
/// is the transport over a `Dio`.
abstract interface class ClientTransport {
  /// Sends [request] and completes with the response of any status once its
  /// headers arrived; the body is read from [TransportResponse.body].
  ///
  /// A request that gets no response, or whose body fails while it is read,
  /// fails with a `TransportException`, of kind `cancelled` when
  /// [TransportRequest.cancel] was cancelled; nothing else is thrown for a
  /// failed request.
  Future<TransportResponse> send(TransportRequest request);
}
