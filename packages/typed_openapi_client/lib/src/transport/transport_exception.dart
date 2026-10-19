/// What kind of failure a [TransportException] reports.
enum TransportExceptionKind {
  /// A connect, send or receive timeout of the transport.
  timeout,

  /// The connection could not be made or broke: refused, reset, closed
  /// early, a certificate the transport rejected.
  connection,

  /// The call's `CancelSignal` was cancelled.
  cancelled,

  /// Any other failure the transport reports.
  other,
}

/// A request that got no complete response: what a `ClientTransport`
/// throws, and what `TransportError` and `Cancelled` carry.
///
/// A transport maps its own failures to this type and throws nothing else
/// for a failed request. [cause] is the transport's own exception (a
/// `DioException` for `typed_openapi_dio`); code that needs its details
/// casts it.
final class TransportException implements Exception {
  /// Creates the exception of a failure of [kind].
  const TransportException(
    this.kind,
    this.message, {
    this.cause,
    this.stackTrace,
  });

  /// What kind of failure it is.
  final TransportExceptionKind kind;

  /// A description for people.
  final String message;

  /// The transport's own exception, or null.
  final Object? cause;

  /// Where [cause] was raised, or null.
  final StackTrace? stackTrace;

  @override
  String toString() => 'TransportException(${kind.name}): $message';
}
