import '../json/json_decode_exception.dart';
import 'sse_message.dart';

/// One item of an open event stream: an [SseEvent], an [SseDecodeError]
/// for one event that did not decode (the stream goes on), or
/// [SseDisconnected], always the last item. The stream never emits errors.
///
/// ```dart
/// await for (final item in events) {
///   switch (item) {
///     case SseEvent(:final data): show(data);
///     case SseDecodeError(:final error): log(error);
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

/// The end of the stream: the server closed it ([cause] is `null`) or the
/// connection failed ([cause] is the error, usually a `DioException`, also
/// for a cancelled request). Always the last item.
final class SseDisconnected<T> extends SseItem<T> {
  /// Creates the last item.
  const SseDisconnected({this.cause, this.stackTrace});

  /// Why the stream ended, or `null` when the server closed it.
  final Object? cause;

  /// Where [cause] was raised.
  final StackTrace? stackTrace;

  @override
  String toString() => 'SseDisconnected(${cause ?? 'closed by server'})';
}
