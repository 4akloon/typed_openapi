import 'dart_type.dart';
import 'event_union_ir.dart';
import 'stream_reconnection.dart';

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
