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
  const EventStreamIr({this.data, this.reconnection = .onRequest});

  /// The type the JSON data of each event decodes to; null when the data
  /// is text, a `String`.
  final DartType? data;

  /// How the stream reconnects.
  final StreamReconnection reconnection;
}
