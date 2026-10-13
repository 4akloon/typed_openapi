import '../diagnostics/json_pointer.dart';

/// Which methods an operation with an event stream gets (`sse.method`).
enum SseMethod {
  /// The stream method beside the JSON method, when there is one.
  stream,

  /// Only the stream method, named as the operation.
  only,

  /// No stream method.
  none,
}

/// The `sse` field of an operation override (decision 6 of M10): what the
/// events of its stream are, what happens to unknown events, whether it
/// reconnects and which methods it gets. [data] and [events] are spec
/// fields, written into the event-stream media types of the operation;
/// the rest are generation fields the IR builder reads.
final class SseOverride {
  /// Creates the field read at [pointer].
  const SseOverride({
    required this.pointer,
    this.data,
    this.events,
    this.keepUnknown,
    this.reconnect,
    this.method,
  });

  /// Where `sse` is in the overrides file.
  final JsonPointer pointer;

  /// The schema of every event's data, as the spec writes it: an inline
  /// schema, or `{$ref: ...}` for a `components.schemas` key.
  final Map<String, Object?>? data;

  /// The events by name, in the order of the file, each with the schema of
  /// its data as [data] has it, or null for an event without data.
  final Map<String, Map<String, Object?>?>? events;

  /// `unknown`: whether an event no name matches is kept (`keep`) or
  /// dropped (`ignore`); null when not set.
  final bool? keepUnknown;

  /// `reconnect`: whether the stream reconnects unless the call says no
  /// (`true`, also for a POST) or never (`false`).
  final bool? reconnect;

  /// `method`: which methods the operation gets.
  final SseMethod? method;

  /// The schema that refers to the `components.schemas` key [name].
  static Map<String, Object?> component(String name) {
    final pointer = JsonPointer.root
        .child('components')
        .child('schemas')
        .child(name);
    // A `$ref` is a URI: a `%` or a space in the key is percent-encoded.
    return {r'$ref': Uri(fragment: pointer.value.substring(1)).toString()};
  }
}
