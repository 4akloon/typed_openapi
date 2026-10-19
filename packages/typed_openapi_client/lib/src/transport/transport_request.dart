import '../request/operation_info.dart';
import 'cancel_signal.dart';

/// A finished HTTP request, built by the client core for a
/// `ClientTransport`.
final class TransportRequest {
  /// Creates a request of [operation].
  const TransportRequest({
    required this.method,
    required this.target,
    required this.operation,
    this.headers = const {},
    this.body,
    this.cancel,
    this.extra = const {},
    this.isEventStream = false,
  });

  /// The HTTP method in upper case.
  final String method;

  /// The path with the encoded query, such as `/pets/7?fields=a,b`, exactly
  /// as the core built it; the transport resolves it against its own base
  /// URL.
  final String target;

  /// The operation of the spec this request calls, for the transport's
  /// interceptors and logs (its tags and security metadata).
  final OperationInfo operation;

  /// The headers to send, in order: a name maps to its values, each sent as
  /// given. `Content-Length` is here when the length of [body] is known.
  final Map<String, List<String>> headers;

  /// The body, read once; null for none.
  final Stream<List<int>>? body;

  /// Cancels the request; null when the call cannot be cancelled.
  final CancelSignal? cancel;

  /// Data of the call for the transport (`CallOptions.extra`).
  final Map<String, Object?> extra;

  /// Whether the response is an event stream, read as it arrives: a
  /// transport that buffers whole responses cannot serve it.
  final bool isEventStream;

  /// The value of `Content-Length` in [headers], or null.
  int? get contentLength {
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == 'content-length' && value.isNotEmpty) {
        return int.tryParse(value.first);
      }
    }
    return null;
  }

  @override
  String toString() => '$method $target';
}
