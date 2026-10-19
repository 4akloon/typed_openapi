import '../sse/sse_options.dart';
import '../transport/cancel_signal.dart';

/// Per-call options: the optional `call` parameter of every generated
/// method.
///
/// One object instead of many named parameters, so that a new option does
/// not change the signature of generated methods (and of user fakes that
/// implement them). Base URL, timeouts and retries belong to the transport.
final class CallOptions {
  /// Creates per-call options.
  const CallOptions({
    this.cancel,
    this.headers = const {},
    this.extra = const {},
    this.onSendProgress,
    this.onReceiveProgress,
    this.sse,
  });

  /// Cancels the call; the operation then returns `Cancelled`, and an event
  /// stream ends with `SseDisconnected`.
  final CancelSignal? cancel;

  /// Headers added to the request; they win over the headers the operation
  /// sends for its header parameters, case-insensitively. A value that is a
  /// list is sent as one value per item; a `null` value is not sent. The
  /// one exception is `Content-Type`: the operation's own content type
  /// (`OperationRequest.contentType`, set for a request body) wins over a
  /// `Content-Type` given here, so it cannot be used to pick another media
  /// type such as `application/merge-patch+json`.
  ///
  /// For an event stream a `Last-Event-ID` given here is where the stream's
  /// last event id starts, as it would for `EventSource`: it goes with the
  /// first request and with a reconnection until an event's `id` replaces
  /// it, and an empty `id:` removes it. It is sent only when it is a valid
  /// header value (printable ASCII).
  final Map<String, Object?> headers;

  /// Data for the transport (`TransportRequest.extra`); `typed_openapi_dio`
  /// merges it into `RequestOptions.extra` for interceptors.
  final Map<String, Object?> extra;

  /// Reports the bytes of the request body sent so far and its length.
  final void Function(int count, int total)? onSendProgress;

  /// Reports the bytes of the response body received so far and its
  /// `Content-Length`, `-1` without one.
  final void Function(int count, int total)? onReceiveProgress;

  /// How an event stream reconnects; null for the defaults of
  /// [SseOptions]. Other operations ignore it.
  final SseOptions? sse;
}
