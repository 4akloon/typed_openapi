import 'dart:async';

import 'sse_item.dart';
import 'sse_tracer.dart';

/// Passes the items of an event stream on unchanged and traces what only
/// the whole stream knows: the errors that end connections, the waits
/// before reconnection and the end (`SseTraceKind.error`, `reconnecting`,
/// `closed`).
final class TracedItems<T>
    extends StreamTransformerBase<SseItem<T>, SseItem<T>> {
  /// Creates the wrapper that reports to [tracer].
  const TracedItems(this.tracer);

  /// Where the traces go.
  final SseTracer tracer;

  @override
  Stream<SseItem<T>> bind(Stream<SseItem<T>> stream) =>
      _Traced<T>(tracer).start(stream);
}

/// The state of one traced stream.
final class _Traced<T> {
  _Traced(this._tracer);

  final SseTracer _tracer;
  // Set in start, before anything can listen.
  late final StreamController<SseItem<T>> _out;
  StreamSubscription<SseItem<T>>? _source;
  bool _isClosed = false;

  Stream<SseItem<T>> start(Stream<SseItem<T>> stream) {
    _out = StreamController<SseItem<T>>(
      onListen: () {
        _source = stream.listen(
          _onItem,
          onError: _out.addError,
          onDone: _out.close,
        );
      },
      onPause: () => _source?.pause(),
      onResume: () => _source?.resume(),
      onCancel: () {
        _close();
        return _source?.cancel();
      },
    );
    return _out.stream;
  }

  void _onItem(SseItem<T> item) {
    switch (item) {
      case SseReconnecting(:final attempt, :final delay, :final cause):
        if (cause != null) _tracer.error(cause, item.stackTrace);
        _tracer.reconnecting(attempt, delay);
      case SseDisconnected(:final cause):
        if (cause != null) _tracer.error(cause, item.stackTrace);
        _close();
      case SseEvent() || SseDecodeError():
        break;
    }
    _out.add(item);
  }

  void _close() {
    if (_isClosed) return;
    _isClosed = true;
    _tracer.closed();
  }
}
