import '../model/spec_node.dart';
import 'event_variant_ir.dart';

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

  /// This union, keeping unknown events when [keepUnknown].
  EventUnionIr keeping({required bool keepUnknown}) => EventUnionIr(
    variants,
    location: location,
    keepUnknown: keepUnknown,
    unknownSensitive: unknownSensitive,
  );

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
