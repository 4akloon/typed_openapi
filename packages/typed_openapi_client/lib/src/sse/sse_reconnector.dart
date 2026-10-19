import 'dart:async';

import '../result/result.dart';
import '../transport/cancel_signal.dart';
import '../transport/transport_exception.dart';
import 'cancellable_wait.dart';
import 'sse_item.dart';
import 'sse_options.dart';

/// Where a new connection of an event stream picks up: the last event id
/// (sent as `Last-Event-ID`) and the server's last reconnection time.
typedef SseResume = ({String lastEventId, Duration? retry});

/// Keeps an event stream going across connections (R12.5).
///
/// When a connection ends ([SseDisconnected] from the server closing it or
/// from a failed connection), the stream emits [SseReconnecting], waits,
/// and calls [reopen] with the last event id. A new connection's items
/// follow; a failed attempt (a [TransportError]) is the next attempt. The
/// stream ends with [SseDisconnected] when [SseOptions.maxAttempts]
/// attempts in a row bring no message, when the request is cancelled (the
/// listener cancels, or [cancel] is cancelled, also during a wait), when
/// the server answers an attempt with a status that is not a stream (the
/// `Failure` is the cause), or with 204 No Content, which tells a client
/// to stop reconnecting.
final class SseReconnector<T>
    extends StreamTransformerBase<SseItem<T>, SseItem<T>> {
  /// Creates the reconnection of one call.
  const SseReconnector(
    this.options,
    this.reopen, {
    this.cancel,
    this.onCancel,
  });

  /// The delays and the number of attempts.
  final SseOptions options;

  /// Opens the stream again from a [SseResume].
  final Future<Result<Stream<SseItem<T>>, Object?>> Function(SseResume resume)
  reopen;

  /// The call's cancel signal.
  final CancelSignal? cancel;

  /// Called when the listener cancels the stream, to abort a request that
  /// [reopen] has in flight.
  final void Function()? onCancel;

  @override
  Stream<SseItem<T>> bind(Stream<SseItem<T>> stream) =>
      _Reconnection<T>(this).start(stream);
}

/// The state of one reconnecting stream.
final class _Reconnection<T> {
  _Reconnection(this._owner) : _sleep = CancellableWait(_owner.options.wait);

  final SseReconnector<T> _owner;
  final CancellableWait _sleep;
  // Set in start, before anything can listen.
  late final StreamController<SseItem<T>> _out;
  StreamSubscription<SseItem<T>>? _current;
  String _lastEventId = '';
  Duration? _retry;
  int _attempt = 0;
  bool _closed = false;
  TransportException? _cancel;
  // Read once: every wait races the same future, and a signal is asked for
  // it once per call, not once per reconnection.
  Future<void>? _cancelled;

  Stream<SseItem<T>> start(Stream<SseItem<T>> first) {
    _cancelled = _owner.cancel?.whenCancelled;
    _cancelled?.then((_) {
      _cancel = TransportException(
        .cancelled,
        'The call was cancelled.',
        cause: _owner.cancel?.reason,
        stackTrace: StackTrace.current,
      );
      _sleep.cancel();
    });
    _out = StreamController<SseItem<T>>(
      onListen: () => _listen(first),
      onPause: () => _current?.pause(),
      onResume: () => _current?.resume(),
      onCancel: () {
        _closed = true;
        _sleep.cancel();
        _owner.onCancel?.call();
        return _current?.cancel();
      },
    );
    return _out.stream;
  }

  void _listen(Stream<SseItem<T>> stream) {
    // An Error of the event decoder: a bug, forwarded as M7 does.
    _current = stream.listen(_onItem, onError: _fail);
    // The listener may have paused during a wait or a reopen, when there
    // was no connection to pause.
    if (_out.isPaused) _current?.pause();
  }

  /// Ends the stream with [error], which user code threw: the one error a
  /// stream gives.
  void _fail(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    _out
      ..addError(error, stackTrace)
      ..close();
  }

  void _onItem(SseItem<T> item) {
    switch (item) {
      case SseEvent(:final id, :final retry):
        _remember(id, retry);
        _out.add(item);
      case SseDecodeError(:final message):
        _remember(message.id, message.retry);
        _out.add(item);
      case SseReconnecting():
        _out.add(item);
      case SseDisconnected(cause: TransportException(kind: .cancelled)):
        _end(item);
      case SseDisconnected(:final cause, :final stackTrace):
        // A dropped event (SseEventIgnored) still moves the id and counts as
        // progress: the connection worked.
        _lastEventId = item.lastEventId;
        if (item.retry case final retry?) _retry = retry;
        if (item.receivedMessage) _attempt = 0;
        _current = null;
        unawaited(_reconnect(cause, stackTrace));
    }
  }

  void _remember(String id, Duration? retry) {
    _lastEventId = id;
    _retry = retry;
    _attempt = 0;
  }

  Future<void> _reconnect(Object? cause, StackTrace? stackTrace) async {
    try {
      await _nextConnection(cause, stackTrace);
    } on Object catch (error, trace) {
      // Not awaited by anyone: an escaping error would hang the stream and
      // reach the zone. It comes from user code (a `wait` or an interceptor)
      // or from the transport, and is a bug as an Error in a decoder is.
      _fail(error, trace);
    }
  }

  /// Waits and opens the next connection after the end of one for [cause].
  Future<void> _nextConnection(Object? cause, StackTrace? stackTrace) async {
    final options = _owner.options;
    if (_attempt >= options.maxAttempts) {
      return _end(_disconnected(cause, stackTrace));
    }
    _attempt++;
    final delay = options.delayBefore(_attempt, _retry);
    _out.add(
      SseReconnecting(_attempt, delay, cause: cause, stackTrace: stackTrace),
    );
    await _wait(delay);
    if (_closed) return;
    if (_cancel case final cancel?) {
      return _end(_disconnected(cancel, cancel.stackTrace));
    }
    _resume(await _owner.reopen((lastEventId: _lastEventId, retry: _retry)));
  }

  /// Goes on with the [result] of an attempt.
  void _resume(Result<Stream<SseItem<T>>, Object?> result) {
    final isNoContent = switch (result) {
      Success(statusCode: 204) => true,
      _ => false,
    };
    if (_closed || isNoContent) {
      // Listening and cancelling closes the connection of the response.
      if (result case Success(:final data)) data.listen(null).cancel();
      _end(_disconnected(null, null));
      return;
    }
    switch (result) {
      case Success(:final data):
        _listen(data);
      case TransportError(:final exception, :final stackTrace):
        unawaited(_reconnect(exception, stackTrace));
      case Cancelled(:final exception, :final stackTrace):
        _end(_disconnected(exception, stackTrace));
      case final Failure<Stream<SseItem<T>>, Object?> failure:
        _end(_disconnected(failure, null));
    }
  }

  Future<void> _wait(Duration delay) {
    final wait = _sleep.wait(delay);
    final cancelled = _cancelled;
    return cancelled == null ? wait : Future.any([wait, cancelled]);
  }

  /// The last item of the stream: it carries the last event id and retry
  /// the stream saw.
  SseDisconnected<T> _disconnected(Object? cause, StackTrace? stackTrace) =>
      SseDisconnected(
        cause: cause,
        stackTrace: stackTrace,
        lastEventId: _lastEventId,
        retry: _retry,
      );

  void _end(SseDisconnected<T> last) {
    if (_closed) return;
    _closed = true;
    _out
      ..add(last)
      ..close();
  }
}
