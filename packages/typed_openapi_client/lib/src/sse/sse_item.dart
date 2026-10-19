import '../json/json_decode_exception.dart';
import 'sse_message.dart';

/// One item of an open event stream: an [SseEvent], an [SseDecodeError]
/// for one event that did not decode (the stream goes on), an
/// [SseReconnecting] before each reconnection attempt, or
/// [SseDisconnected], always the last item. The stream never emits errors.
///
/// ```dart
/// await for (final item in events) {
///   switch (item) {
///     case SseEvent(:final data): show(data);
///     case SseDecodeError(:final error): log(error);
///     case SseReconnecting(:final attempt): showRetrying(attempt);
///     case SseDisconnected(): break;
///   }
/// }
/// ```
sealed class SseItem<T> {
  const SseItem();
}

/// An event whose data decoded as [T].
final class SseEvent<T> extends SseItem<T> {
  /// Creates an event.
  const SseEvent(this.data, {this.event = 'message', this.id = '', this.retry});

  /// The decoded data.
  final T data;

  /// The `event` field, or `message`.
  final String event;

  /// The last event id seen in the stream so far, or `''`.
  final String id;

  /// The last reconnection time the server asked for, or `null`.
  final Duration? retry;

  @override
  String toString() => 'SseEvent($event, id: $id)';
}

/// An event whose data does not match its schema; later events still come.
final class SseDecodeError<T> extends SseItem<T> {
  /// Creates a decode error for [message].
  const SseDecodeError(this.error, this.message);

  /// What did not match and where.
  final JsonDecodeException error;

  /// The event as received.
  final SseMessage message;

  @override
  String toString() => 'SseDecodeError(${message.event}: $error)';
}

/// The connection ended and the stream reconnects after [delay] (R12.5):
/// attempt number [attempt], counted from 1 since the last event.
final class SseReconnecting<T> extends SseItem<T> {
  /// Creates the item of [attempt].
  const SseReconnecting(
    this.attempt,
    this.delay, {
    this.cause,
    this.stackTrace,
  });

  /// The number of the attempt, from 1.
  final int attempt;

  /// How long the stream waits before the attempt.
  final Duration delay;

  /// Why the last connection ended: null when the server closed it, else
  /// the error (usually a `DioException`).
  final Object? cause;

  /// Where [cause] was raised.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'SseReconnecting($attempt after $delay${cause == null ? '' : ': $cause'})';
}

/// The end of the stream: the server closed it ([cause] is `null`) or the
/// connection failed ([cause] is the error, usually a `DioException`, also
/// for a cancelled request). When the stream reconnects, it comes after
/// the last attempt, and a reconnection the server answers with another
/// status ends the stream with that `Failure` as [cause]. Always the last
/// item.
final class SseDisconnected<T> extends SseItem<T> {
  /// Creates the last item.
  const SseDisconnected({
    this.cause,
    this.stackTrace,
    this.lastEventId = '',
    this.retry,
    this.receivedMessage = false,
  });

  /// Why the stream ended, or `null` when the server closed it.
  final Object? cause;

  /// Where [cause] was raised.
  final StackTrace? stackTrace;

  /// The last event id of the stream when it ended, `''` when it had none
  /// (as [SseEvent.id]): also the id of an event the decoder dropped
  /// (`SseEventIgnored`) and of a block without data, as WHATWG sets it at
  /// every empty line. A reconnection sends it as `Last-Event-ID`.
  final String lastEventId;

  /// The last reconnection time of the stream when it ended, or null.
  final Duration? retry;

  /// Whether the connection delivered at least one message: an event, an
  /// event that did not decode, or one the decoder dropped. A reconnecting
  /// stream starts its count of failed attempts again after such a
  /// connection, so a stream that only carries events the program ignores
  /// (heartbeats) is not given up.
  final bool receivedMessage;

  @override
  String toString() => 'SseDisconnected(${cause ?? 'closed by server'})';
}
