import 'package:dio/dio.dart';

import '../sse/sse_options.dart';

/// Per-call options: the optional `call` parameter of every generated
/// method.
///
/// One object instead of many named parameters, so that a new option does
/// not change the signature of generated methods (and of user fakes that
/// implement them). Base URL, timeouts and retries belong to the user's
/// Dio and its interceptors.
final class CallOptions {
  /// Creates per-call options.
  const CallOptions({
    this.cancelToken,
    this.headers = const {},
    this.extra = const {},
    this.onSendProgress,
    this.onReceiveProgress,
    this.sse,
  });

  /// Cancels the request; the operation then returns `Cancelled`.
  final CancelToken? cancelToken;

  /// Headers added to the request; they win over the headers the operation
  /// sends for its header parameters, case-insensitively. The one exception
  /// is `Content-Type`: the operation's own content type
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

  /// Data for interceptors, merged into `RequestOptions.extra`.
  final Map<String, Object?> extra;

  /// Reports sent bytes.
  final ProgressCallback? onSendProgress;

  /// Reports received bytes.
  final ProgressCallback? onReceiveProgress;

  /// How an event stream reconnects; null for the defaults of
  /// [SseOptions]. Other operations ignore it.
  final SseOptions? sse;
}
