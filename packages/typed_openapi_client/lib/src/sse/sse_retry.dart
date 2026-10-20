import '../result/result.dart';

/// Decides whether a failed attempt to open an event stream is worth
/// retrying.
///
/// The same rule serves the first opening and every reconnection; a call
/// replaces it with `SseOptions.retryWhen`, which can extend it by calling
/// [isTransient].
///
/// | Failure | Result |
/// | --- | --- |
/// | [Cancelled] | final |
/// | [TransportError] `connection` or `timeout` | transient |
/// | [TransportError] `other` | final |
/// | status 408, 429, and every 5xx but 501 and 505 | transient |
/// | any other status, or a [DecodeError] without one | final |
///
/// The status is read from [HttpError], [UndocumentedStatus] and
/// [DecodeError]: a 503 from a proxy is the same event whether or not the
/// spec documents it.
// ignore: avoid_classes_with_only_static_members, a namespace the plan names (SseRetry.isTransient) so a user override can call it.
abstract final class SseRetry {
  /// Whether trying again can help after [failure].
  static bool isTransient(Failure<Object?, Object?> failure) =>
      switch (failure) {
        Cancelled() => false,
        TransportError(:final exception) =>
          exception.kind == .connection || exception.kind == .timeout,
        HttpError(:final statusCode) => _isTransientStatus(statusCode),
        UndocumentedStatus(:final statusCode) => _isTransientStatus(statusCode),
        DecodeError(:final statusCode?) => _isTransientStatus(statusCode),
        DecodeError() => false,
      };

  static bool _isTransientStatus(int status) =>
      status == 408 ||
      status == 429 ||
      (status >= 500 && status != 501 && status != 505);
}
