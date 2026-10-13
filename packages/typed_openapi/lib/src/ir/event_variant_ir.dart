import '../model/spec_node.dart';
import 'dart_type.dart';

/// One event of an [EventUnionIr].
final class EventVariantIr {
  /// Creates the variant of the event named [event].
  const EventVariantIr(
    this.event, {
    required this.location,
    this.name = '',
    this.hasData = true,
    this.data,
    this.sensitive = false,
  });

  /// The event name as the spec writes it (the SSE `event` field).
  final String event;

  /// Where the variant is described: its branch of the `itemSchema`, or the
  /// override's schema.
  final SpecLocation location;

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
    location: location,
    name: name,
    hasData: hasData,
    data: data,
    sensitive: sensitive,
  );
}
