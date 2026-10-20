import 'dart:async';

import '../result/result.dart';
import '../transport/cancel_signal.dart';
import '../transport/transport_exception.dart';
import 'cancellable_wait.dart';
import 'reconnection_plan.dart';
import 'sse_item.dart';
import 'sse_settings.dart';

/// Where a new connection of an event stream picks up: the last event id
/// (sent as `Last-Event-ID`) and the server's last reconnection time.
typedef SseResume = ({String lastEventId, Duration? retry});

/// Keeps an event stream going across connections (R12.5).
///
/// When a connection ends ([SseDisconnected] from the server closing it or
/// from a failed connection), the stream emits [SseReconnecting], waits,
/// and calls [reopen] with the last event id. A new connection's items
/// follow; a failed attempt that [SseSettings.shouldRetry] accepts is the
/// next attempt, and a `Retry-After` of its response lengthens the wait.
/// The stream ends with [SseDisconnected] when [SseSettings.maxAttempts]
/// attempts in a row bring no message (never, when it is null), when the
/// request is cancelled (the listener cancels, or [cancel] is cancelled,
/// also during a wait), when an attempt fails in a way that
/// [SseSettings.shouldRetry] refuses (the `Failure` is the cause), or with
/// 204 No Content, which tells a client to stop reconnecting.
final class SseReconnector<T>
    extends StreamTransformerBase<SseItem<T>, SseItem<T>> {
  /// Creates the reconnection of one call.
  const SseReconnector(
    this.settings,
    this.plan,
    this.reopen, {
    this.cancel,
    this.onCancel,
  });

  /// The call's settings: the classifier, the clock of the waits.
  final SseSettings settings;

  /// The delays and the number of attempts, shared with the opening.
  final ReconnectionPlan plan;

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
  _Reconnection(this._owner)
    : _sleep = CancellableWait(_owner.settings.wait),
      _plan = _owner.plan;

  final SseReconnector<T> _owner;
  final CancellableWait _sleep;
  final ReconnectionPlan _plan;
  // Set in start, before anything can listen.
  late final StreamController<SseItem<T>> _out;
  StreamSubscription<SseItem<T>>? _current;
  String _lastEventId = '';
  Duration? _retry;
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
        if (item.receivedMessage) _plan.reset();
        _current = null;
        unawaited(_reconnect(cause, stackTrace));
    }
  }

  void _remember(String id, Duration? retry) {
    _lastEventId = id;
    _retry = retry;
    _plan.reset();
  }

  Future<void> _reconnect(
    Object? cause,
    StackTrace? stackTrace, [
    Failure<Object?, Object?>? failure,
  ]) async {
    try {
      await _nextConnection(cause, stackTrace, failure);
    } on Object catch (error, trace) {
      // Not awaited by anyone: an escaping error would hang the stream and
      // reach the zone. It comes from user code (a `wait` or an interceptor)
      // or from the transport, and is a bug as an Error in a decoder is.
      _fail(error, trace);
    }
  }

  /// Waits and opens the next connection after the end of one for [cause];
  /// [failure] is the answer of a failed attempt, whose `Retry-After`
  /// counts.
  Future<void> _nextConnection(
    Object? cause,
    StackTrace? stackTrace,
    Failure<Object?, Object?>? failure,
  ) async {
    final step = _plan.next(_retry, failure: failure);
    if (step == null) return _end(_disconnected(cause, stackTrace));
    final (:attempt, :delay) = step;
    _out.add(
      SseReconnecting(attempt, delay, cause: cause, stackTrace: stackTrace),
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
      case Cancelled(:final exception, :final stackTrace):
        _end(_disconnected(exception, stackTrace));
      case final Failure<Stream<SseItem<T>>, Object?> failure:
        final (cause, stackTrace) = switch (failure) {
          TransportError(:final exception, :final stackTrace) => (
            exception,
            stackTrace,
          ),
          _ => (failure, null),
        };
        if (_owner.settings.shouldRetry(failure)) {
          unawaited(_reconnect(cause, stackTrace, failure));
        } else {
          _end(_disconnected(cause, stackTrace));
        }
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
