import 'dart:async';

import '../json/json_decode_exception.dart';
import 'sse_decoder.dart';
import 'sse_event_ignored.dart';
import 'sse_item.dart';
import 'sse_message.dart';

/// Decodes a `text/event-stream` body into [SseItem]s: each message goes
/// through [decode] (a generated function, usually over
/// [SseMessage.jsonObject]); an event it throws [SseEventIgnored] for is
/// dropped; a [JsonDecodeException] or a [FormatException]
/// (a converter or `Date.parse` rejecting the data) becomes an
/// [SseDecodeError] and the stream goes on. The end of the body, or its
/// first error, becomes [SseDisconnected] and closes the stream, so the
/// stream never emits errors, with one exception: an [Error] thrown by
/// [decode] is a bug of the program, not a problem of the data, so it is
/// forwarded as a stream error and the stream closes. Cancelling the
/// subscription cancels the body.
final class SseItemDecoder<T>
    extends StreamTransformerBase<List<int>, SseItem<T>> {
  /// Creates a decoder whose events [decode] reads; the stream's state
  /// starts from [lastEventId] and [retry] (see [SseDecoder]).
  const SseItemDecoder(
    this.decode, {
    this.onClose,
    this.lastEventId = '',
    this.retry,
  });

  /// Reads the data of one event.
  final T Function(SseMessage message) decode;

  /// Called exactly once per listened stream, whichever way it ends: the
  /// body ended, the body failed, the listener cancelled (however often), or
  /// [decode] threw an [Error]. Never called for a stream nobody listens to.
  /// `openEvents` closes the connection here.
  final void Function()? onClose;

  /// The last event id before the stream starts.
  final String lastEventId;

  /// The reconnection time before the stream starts.
  final Duration? retry;

  @override
  Stream<SseItem<T>> bind(Stream<List<int>> stream) =>
      _Decoding<T>(this).start(stream);

  /// The item of [message]; null for an event the decoder drops.
  SseItem<T>? _item(SseMessage message) {
    try {
      return SseEvent(
        decode(message),
        event: message.event,
        id: message.id,
        retry: message.retry,
      );
    } on SseEventIgnored {
      return null;
    } on JsonDecodeException catch (e) {
      return SseDecodeError(e, message);
    } on FormatException catch (e) {
      // A user converter or `Date.parse` rejecting the data of one event.
      return SseDecodeError(
        JsonDecodeException.fromFormatException(e),
        message,
      );
    }
  }
}

/// The state of one decoded stream.
final class _Decoding<T> {
  _Decoding(this._owner)
    : _lastId = _owner.lastEventId,
      _lastRetry = _owner.retry;

  final SseItemDecoder<T> _owner;
  // Set in start, before anything can listen.
  late final StreamController<SseItem<T>> _items;
  StreamSubscription<SseMessage>? _source;
  bool _closed = false;
  // What the last item carries: also the id of a dropped event.
  String _lastId;
  Duration? _lastRetry;
  bool _receivedMessage = false;

  Stream<SseItem<T>> start(Stream<List<int>> stream) {
    _items = StreamController<SseItem<T>>(
      onListen: () => _listen(stream),
      onPause: () => _source?.pause(),
      onResume: () => _source?.resume(),
      onCancel: () {
        _close();
        return _source?.cancel();
      },
    );
    return _items.stream;
  }

  void _listen(Stream<List<int>> stream) {
    _source = SseDecoder(lastEventId: _owner.lastEventId, retry: _owner.retry)
        .bind(stream)
        .listen(
          _onMessage,
          onError: (Object error, StackTrace stackTrace) =>
              _end(cause: error, stackTrace: stackTrace),
          onDone: _end,
          cancelOnError: true,
        );
  }

  void _onMessage(SseMessage message) {
    _lastId = message.id;
    _lastRetry = message.retry;
    _receivedMessage = true;
    final SseItem<T>? item;
    try {
      item = _owner._item(message);
      // ignore: avoid_catching_errors, forwarded to the listener
    } on Error catch (error, stackTrace) {
      _items.addError(error, stackTrace);
      _source?.cancel();
      _close();
      _items.close();
      return;
    }
    if (item != null) _items.add(item);
  }

  /// Ends the stream with [SseDisconnected], which carries the stream's
  /// last event id and retry.
  void _end({Object? cause, StackTrace? stackTrace}) {
    _items
      ..add(
        SseDisconnected(
          cause: cause,
          stackTrace: stackTrace,
          lastEventId: _lastId,
          retry: _lastRetry,
          receivedMessage: _receivedMessage,
        ),
      )
      ..close();
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _owner.onClose?.call();
  }
}
