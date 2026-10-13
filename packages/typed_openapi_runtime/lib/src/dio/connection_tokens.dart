import 'package:dio/dio.dart';

/// The cancel tokens of the connections of one event-stream call.
///
/// Each connection has a token of its own, so closing a stream cancels its
/// connection and not the call's token; the call's token ([outer]) cancels
/// whichever connection is current. The call's token gets one listener, not
/// one per connection.
final class ConnectionTokens {
  /// Links the connections of a call whose cancel token is [outer].
  ConnectionTokens(this._outer) {
    _outer?.whenCancel.then((e) => cancel(e.error));
  }

  final CancelToken? _outer;
  CancelToken? _current;

  /// The token of a new connection, which becomes the current one.
  CancelToken next() {
    final token = CancelToken();
    final outer = _outer;
    if (outer != null && outer.isCancelled) {
      token.cancel(outer.cancelError?.error);
    }
    return _current = token;
  }

  /// Cancels the current connection, for [reason]: the listener of the
  /// stream cancelled, or the call's token did.
  void cancel([Object? reason]) {
    final token = _current;
    if (token != null && !token.isCancelled) token.cancel(reason);
  }
}
