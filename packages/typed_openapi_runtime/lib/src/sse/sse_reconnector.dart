import 'dart:async';

import 'package:dio/dio.dart';

import '../result/result.dart';
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
/// attempts in a row bring no event, when the request is cancelled (the
/// listener cancels, or [cancelled] completes, also during a wait), when
/// the server answers an attempt with a status that is not a stream (the
/// `Failure` is the cause), or with 204 No Content, which tells a client
/// to stop reconnecting.
final class SseReconnector<T>
    extends StreamTransformerBase<SseItem<T>, SseItem<T>> {
  /// Creates the reconnection of one call.
  const SseReconnector(this.options, this.reopen, {this.cancelled});

  /// The delays and the number of attempts.
  final SseOptions options;

  /// Opens the stream again from a [SseResume].
  final Future<Result<Stream<SseItem<T>>, Object?>> Function(SseResume resume)
  reopen;

  /// Completes when the call's cancel token is cancelled.
  final Future<DioException>? cancelled;

  @override
  Stream<SseItem<T>> bind(Stream<SseItem<T>> stream) =>
      _Reconnection<T>(this).start(stream);
}

/// The state of one reconnecting stream.
final class _Reconnection<T> {
  _Reconnection(this._owner);

  final SseReconnector<T> _owner;
  // Set in start, before anything can listen.
  late final StreamController<SseItem<T>> _out;
  StreamSubscription<SseItem<T>>? _current;
  String _lastEventId = '';
  Duration? _retry;
  int _attempt = 0;
  bool _closed = false;
  DioException? _cancel;

  Stream<SseItem<T>> start(Stream<SseItem<T>> first) {
    _owner.cancelled?.then((e) => _cancel = e);
    _out = StreamController<SseItem<T>>(
      onListen: () => _listen(first),
      onPause: () => _current?.pause(),
      onResume: () => _current?.resume(),
      onCancel: () {
        _closed = true;
        return _current?.cancel();
      },
    );
    return _out.stream;
  }

  void _listen(Stream<SseItem<T>> stream) {
    _current = stream.listen(
      _onItem,
      onError: (Object error, StackTrace stackTrace) {
        // An Error of the event decoder: a bug, forwarded as M7 does.
        _closed = true;
        _out
          ..addError(error, stackTrace)
          ..close();
      },
    );
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
      case SseDisconnected(cause: DioException(type: .cancel)):
        _end(item);
      case SseDisconnected(:final cause, :final stackTrace):
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
    final options = _owner.options;
    if (_attempt >= options.maxAttempts) {
      return _end(SseDisconnected(cause: cause, stackTrace: stackTrace));
    }
    _attempt++;
    final delay = options.delayBefore(_attempt, _retry);
    _out.add(
      SseReconnecting(_attempt, delay, cause: cause, stackTrace: stackTrace),
    );
    await _wait(delay);
    if (_closed) return;
    if (_cancel case final cancel?) {
      return _end(
        SseDisconnected(cause: cancel, stackTrace: cancel.stackTrace),
      );
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
      _end(const SseDisconnected());
      return;
    }
    switch (result) {
      case Success(:final data):
        _listen(data);
      case TransportError(:final exception, :final stackTrace):
        unawaited(_reconnect(exception, stackTrace));
      case Cancelled(:final exception, :final stackTrace):
        _end(SseDisconnected(cause: exception, stackTrace: stackTrace));
      case final Failure<Stream<SseItem<T>>, Object?> failure:
        _end(SseDisconnected(cause: failure));
    }
  }

  Future<void> _wait(Duration delay) {
    final wait = (_owner.options.wait ?? Future<void>.delayed)(delay);
    final cancelled = _owner.cancelled;
    return cancelled == null ? wait : Future.any([wait, cancelled]);
  }

  void _end(SseDisconnected<T> last) {
    if (_closed) return;
    _closed = true;
    _out
      ..add(last)
      ..close();
  }
}
