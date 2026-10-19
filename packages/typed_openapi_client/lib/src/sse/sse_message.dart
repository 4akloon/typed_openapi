import 'dart:convert';

import '../json/json_decode_exception.dart';
import '../json/json_reader.dart';

/// One event of a `text/event-stream` body before its data is decoded, as
/// the WHATWG event stream format dispatches it.
final class SseMessage {
  /// Creates a message.
  const SseMessage({
    required this.data,
    this.event = 'message',
    this.id = '',
    this.retry,
  });

  /// The `event` field, or `message` when the event has none.
  final String event;

  /// The `data` lines joined by `\n`.
  final String data;

  /// The last `id` seen in the stream so far (it persists across events);
  /// `''` when there was none or an empty `id` reset it. A reconnect sends
  /// it as `Last-Event-ID`.
  final String id;

  /// The last valid `retry` seen in the stream so far: the reconnection
  /// time the server asks for, or `null`.
  final Duration? retry;

  /// [data] parsed as JSON; text that is not JSON, or nesting deeper than
  /// [JsonReader.maxDepth], throws [JsonDecodeException].
  Object? get json {
    final Object? value;
    try {
      value = jsonDecode(data);
    } on FormatException {
      throw JsonDecodeException(
        expected: 'JSON event data',
        actual: 'text that is not JSON',
      );
    }
    JsonReader.checkDepth(value);
    return value;
  }

  /// [data] as a JSON object; anything else throws [JsonDecodeException].
  Map<String, Object?> get jsonObject => JsonReader.asObject(json);

  @override
  bool operator ==(Object other) =>
      other is SseMessage &&
      other.event == event &&
      other.data == data &&
      other.id == id &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(event, data, id, retry);

  @override
  String toString() =>
      'SseMessage(event: $event, data: $data, id: $id, retry: $retry)';
}
