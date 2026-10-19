import '../transport/cancel_signal.dart';

/// The cancel signals of the connections of one event-stream call.
///
/// Each connection has a signal of its own, so closing a stream cancels its
/// connection and not the call's signal; the call's signal ([outer])
/// cancels whichever connection is current. The call's signal gets one
/// listener, not one per connection.
final class ConnectionSignals {
  /// Links the connections of a call whose cancel signal is [outer].
  ConnectionSignals(this._outer) {
    final outer = _outer;
    outer?.whenCancelled.then((_) => cancel(outer.reason));
  }

  final CancelSignal? _outer;
  CancelSignal? _current;

  /// The signal of a new connection, which becomes the current one.
  CancelSignal next() {
    final signal = CancelSignal();
    if (_outer case final outer? when outer.isCancelled) {
      signal.cancel(outer.reason);
    }
    return _current = signal;
  }

  /// Cancels the current connection, for [reason]: the listener of the
  /// stream cancelled, or the call's signal did.
  void cancel([Object? reason]) => _current?.cancel(reason);
}
