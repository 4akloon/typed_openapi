import 'package:dio/dio.dart';

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
  });

  /// Cancels the request; the operation then returns `Cancelled`.
  final CancelToken? cancelToken;

  /// Headers added to the request; they win over the headers the operation
  /// sends for its header parameters.
  final Map<String, Object?> headers;

  /// Data for interceptors, merged into `RequestOptions.extra`.
  final Map<String, Object?> extra;

  /// Reports sent bytes.
  final ProgressCallback? onSendProgress;

  /// Reports received bytes.
  final ProgressCallback? onReceiveProgress;
}
