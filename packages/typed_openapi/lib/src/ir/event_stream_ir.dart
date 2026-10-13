import '../model/spec_node.dart';
import 'dart_type.dart';

/// Whether the stream of an event-stream method reconnects (R12.5), as the
/// runtime's `SseReconnection` says: a GET reconnects when the call asks
/// for it, an operation that enables reconnection (config or override)
/// unless the call says no, any other method never.
enum StreamReconnection {
  /// Never; a call cannot turn it on.
  off,

  /// When the call asks for it.
  onRequest,

  /// Unless the call says no.
  on,
}

/// The events of an event-stream method (R12.1): what the data of each
/// event decodes to and how the stream reconnects.
final class EventStreamIr {
  /// Creates the events of a method.
  const EventStreamIr({
    this.data,
    this.union,
    this.reconnection = .onRequest,
  });

  /// The type the JSON data of each event decodes to; null when the data
  /// is text, a `String`, or when the events are a [union].
  final DartType? data;

  /// The events typed one by one by their event name (R12.2), when the spec
  /// or the override types them so.
  final EventUnionIr? union;

  /// How the stream reconnects.
  final StreamReconnection reconnection;

  /// These events with [union] named.
  EventStreamIr withUnion(EventUnionIr union) =>
      EventStreamIr(data: data, union: union, reconnection: reconnection);
}

/// A sealed type of the events of a stream keyed by the SSE event name
/// (decision 2 of M10): a variant per event and one for unknown events.
final class EventUnionIr {
  /// Creates the union of [variants], described at [location].
  const EventUnionIr(
    this.variants, {
    required this.location,
    this.name = '',
    this.unknownName = '',
    this.keepUnknown = true,
    this.unknownSensitive = false,
  });

  /// The variants, in the order of the spec, one per event name.
  final List<EventVariantIr> variants;

  /// Where the union is described: the `itemSchema`, or the override.
  final SpecLocation location;

  /// The Dart name of the sealed class, given after the declarations.
  final String name;

  /// The class of an event no variant names; given before the variants'.
  final String unknownName;

  /// Whether an unknown event is an item of the [unknownName] variant;
  /// otherwise it is dropped (`sse.unknown: ignore`).
  final bool keepUnknown;

  /// Whether the data of an unknown event may hold a secret, so its
  /// `toString` does not print it: some event's data carries one.
  final bool unknownSensitive;

  /// This union with its names and [variants] named.
  EventUnionIr named(
    String name,
    String unknownName,
    List<EventVariantIr> variants,
  ) => EventUnionIr(
    variants,
    location: location,
    name: name,
    unknownName: unknownName,
    keepUnknown: keepUnknown,
    unknownSensitive: unknownSensitive,
  );
}

/// One event of an [EventUnionIr].
final class EventVariantIr {
  /// Creates the variant of the event named [event].
  const EventVariantIr(
    this.event, {
    this.name = '',
    this.hasData = true,
    this.data,
    this.sensitive = false,
  });

  /// The event name as the spec writes it (the SSE `event` field).
  final String event;

  /// The Dart name of the variant's class, given after the declarations.
  final String name;

  /// Whether the event carries data; an event without data is a class
  /// without fields.
  final bool hasData;

  /// The type the JSON data decodes to; null for text data, a `String`.
  final DartType? data;

  /// Whether the data is a secret that `toString` does not print.
  final bool sensitive;

  /// This variant named [name].
  EventVariantIr named(String name) => EventVariantIr(
    event,
    name: name,
    hasData: hasData,
    data: data,
    sensitive: sensitive,
  );
}
