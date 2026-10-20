import 'dart:async';

import '../transport/cancel_signal.dart';
import '../transport/client_transport.dart';
import '../transport/transport_exception.dart';
import '../transport/transport_request.dart';
import '../transport/transport_response.dart';

/// Bounds the wait for the response headers of one connection attempt
/// (`SseOptions.handshakeTimeout`) and ends it when the connection is
/// cancelled, even for a transport that ignores the cancel.
final class Handshake {
  /// Creates the bound; a null [timeout] waits as long as the transport
  /// does.
  const Handshake(this.timeout);

  /// How long the headers may take, or null for no bound.
  final Duration? timeout;

  /// Sends [request] through [transport]. When the headers do not arrive in
  /// time, [signal] is cancelled, so the transport aborts the request, and
  /// the call throws a [TransportException] of kind timeout; when [signal]
  /// is cancelled first it throws one of kind cancelled. A response that
  /// arrives after either has its body cancelled.
  Future<TransportResponse> send(
    ClientTransport transport,
    TransportRequest request,
    CancelSignal signal,
  ) => _Attempt(signal, timeout).start(transport.send(request));
}

/// The race of one attempt: the response, the timer and the cancel signal;
/// the first to finish wins.
final class _Attempt {
  _Attempt(this._signal, this._timeout);

  final CancelSignal _signal;
  final Duration? _timeout;
  final Completer<TransportResponse> _done = Completer();
  Timer? _timer;

  Future<TransportResponse> start(Future<TransportResponse> sent) {
    sent.then<void>(_onResponse, onError: _onError);
    _signal.whenCancelled.then<void>((_) => _lose(_cancelled()));
    if (_timeout case final limit?) {
      _timer = Timer(limit, () {
        if (_lose(_timedOut(limit))) {
          _signal.cancel('the event stream did not answer in time');
        }
      });
    }
    return _done.future;
  }

  void _onResponse(TransportResponse response) {
    _timer?.cancel();
    if (_done.isCompleted) {
      // Nobody will read it; cancelling closes the connection.
      response.body.listen(null).cancel();
    } else {
      _done.complete(response);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _timer?.cancel();
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }

  /// Fails the attempt with [error]; false when it was already decided.
  bool _lose(TransportException error) {
    if (_done.isCompleted) return false;
    _timer?.cancel();
    _done.completeError(error, StackTrace.current);
    return true;
  }

  TransportException _cancelled() => TransportException(
    .cancelled,
    'The call was cancelled.',
    cause: _signal.reason,
  );

  TransportException _timedOut(Duration limit) => TransportException(
    .timeout,
    'No response headers arrived within $limit.',
  );
}
