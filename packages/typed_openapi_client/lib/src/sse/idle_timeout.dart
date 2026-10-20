import 'dart:async';

import '../transport/transport_exception.dart';

/// Ends a connection's body after [timeout] without a byte.
///
/// Every chunk resets the timer, so comments and heartbeats keep the
/// connection alive. On expiry the source is cancelled, [onIdle] runs (it
/// aborts the request) and the stream fails with a [TransportException] of
/// kind timeout, which `SseItemDecoder` turns into the `cause` of
/// `SseDisconnected`. The timer does not run while the listener is paused:
/// nothing is read then.
final class IdleTimeout extends StreamTransformerBase<List<int>, List<int>> {
  /// Creates the watch over a body, for [timeout].
  const IdleTimeout(this.timeout, {this.onIdle});

  /// The longest silence.
  final Duration timeout;

  /// Called when the silence lasted [timeout], after the source is
  /// cancelled.
  final void Function()? onIdle;

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) =>
      _Watch(this).start(stream);
}

/// The state of one watched body.
final class _Watch {
  _Watch(this._owner);

  final IdleTimeout _owner;
  // Set in start, before anything can listen.
  late final StreamController<List<int>> _out;
  StreamSubscription<List<int>>? _source;
  Timer? _timer;
  bool _isOver = false;

  Stream<List<int>> start(Stream<List<int>> stream) {
    _out = StreamController<List<int>>(
      onListen: () {
        _source = stream.listen(
          _onChunk,
          onError: _fail,
          onDone: _finish,
          cancelOnError: true,
        );
        _arm();
      },
      onPause: () {
        _timer?.cancel();
        _source?.pause();
      },
      onResume: () {
        _source?.resume();
        _arm();
      },
      onCancel: () {
        _timer?.cancel();
        // A source that ended or was cancelled by the timer has nothing to
        // cancel again.
        return _isOver ? null : _source?.cancel();
      },
    );
    return _out.stream;
  }

  void _onChunk(List<int> chunk) {
    _out.add(chunk);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(_owner.timeout, _expire);
  }

  /// A failed body is over: the source cancels itself, and so does the
  /// listener of the decoder.
  void _fail(Object error, StackTrace stackTrace) {
    _isOver = true;
    _timer?.cancel();
    _out
      ..addError(error, stackTrace)
      ..close();
  }

  void _finish() {
    _isOver = true;
    _timer?.cancel();
    _out.close();
  }

  void _expire() {
    _isOver = true;
    _source?.cancel();
    _out
      ..addError(
        TransportException(
          .timeout,
          'No data arrived for ${_owner.timeout}.',
        ),
        StackTrace.current,
      )
      ..close();
    _owner.onIdle?.call();
  }
}
