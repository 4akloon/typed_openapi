import 'dart:async';

import '../json/json_decode_exception.dart';
import 'sse_decoder.dart';
import 'sse_item.dart';
import 'sse_message.dart';

/// Decodes a `text/event-stream` body into [SseItem]s: each message goes
/// through [decode] (a generated function, usually over
/// [SseMessage.jsonObject]); a [JsonDecodeException] or a [FormatException]
/// (a converter or `Date.parse` rejecting the data) becomes an
/// [SseDecodeError] and the stream goes on. The end of the body, or its
/// first error, becomes [SseDisconnected] and closes the stream, so the
/// stream never emits errors, with one exception: an [Error] thrown by
/// [decode] is a bug of the program, not a problem of the data, so it is
/// forwarded as a stream error and the stream closes. Cancelling the
/// subscription cancels the body.
final class SseItemDecoder<T>
    extends StreamTransformerBase<List<int>, SseItem<T>> {
  /// Creates a decoder whose events [decode] reads.
  const SseItemDecoder(this.decode, {this.onClose});

  /// Reads the data of one event.
  final T Function(SseMessage message) decode;

  /// Called exactly once per listened stream, whichever way it ends: the
  /// body ended, the body failed, the listener cancelled (however often), or
  /// [decode] threw an [Error]. Never called for a stream nobody listens to.
  /// `openEvents` closes the connection here.
  final void Function()? onClose;

  @override
  Stream<SseItem<T>> bind(Stream<List<int>> stream) {
    StreamSubscription<SseMessage>? source;
    late final StreamController<SseItem<T>> items;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      onClose?.call();
    }

    void end(SseDisconnected<T> last) {
      items
        ..add(last)
        ..close();
      close();
    }

    items = StreamController<SseItem<T>>(
      onListen: () {
        source = const SseDecoder()
            .bind(stream)
            .listen(
              (message) {
                final SseItem<T> item;
                try {
                  item = _item(message);
                  // ignore: avoid_catching_errors, forwarded to the listener
                } on Error catch (error, stackTrace) {
                  items.addError(error, stackTrace);
                  source?.cancel();
                  close();
                  items.close();
                  return;
                }
                items.add(item);
              },
              onError: (Object error, StackTrace stackTrace) {
                end(SseDisconnected(cause: error, stackTrace: stackTrace));
              },
              onDone: () => end(const SseDisconnected()),
              cancelOnError: true,
            );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        close();
        return source?.cancel();
      },
    );
    return items.stream;
  }

  SseItem<T> _item(SseMessage message) {
    try {
      return SseEvent(
        decode(message),
        event: message.event,
        id: message.id,
        retry: message.retry,
      );
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
