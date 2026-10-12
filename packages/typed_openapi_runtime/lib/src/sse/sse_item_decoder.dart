import 'dart:async';

import '../json/json_decode_exception.dart';
import 'sse_decoder.dart';
import 'sse_item.dart';
import 'sse_message.dart';

/// Decodes a `text/event-stream` body into [SseItem]s: each message goes
/// through [decode] (a generated function, usually over
/// [SseMessage.jsonObject]); a [JsonDecodeException] becomes an
/// [SseDecodeError] and the stream goes on. The end of the body, or its
/// first error, becomes [SseDisconnected] and closes the stream, so the
/// stream never emits errors. Cancelling the subscription cancels the body.
final class SseItemDecoder<T>
    extends StreamTransformerBase<List<int>, SseItem<T>> {
  /// Creates a decoder whose events [decode] reads.
  const SseItemDecoder(this.decode);

  /// Reads the data of one event.
  final T Function(SseMessage message) decode;

  @override
  Stream<SseItem<T>> bind(Stream<List<int>> stream) {
    StreamSubscription<SseMessage>? source;
    late final StreamController<SseItem<T>> items;
    void end(SseDisconnected<T> last) {
      items
        ..add(last)
        ..close();
    }

    items = StreamController<SseItem<T>>(
      onListen: () {
        source = const SseDecoder()
            .bind(stream)
            .listen(
              (message) => items.add(_item(message)),
              onError: (Object error, StackTrace stackTrace) {
                end(SseDisconnected(cause: error, stackTrace: stackTrace));
              },
              onDone: () => end(const SseDisconnected()),
              cancelOnError: true,
            );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () => source?.cancel(),
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
    }
  }
}
