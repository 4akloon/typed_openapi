/// Thrown by a generated event decoder for an event the stream drops
/// (`sse.unknown: ignore` in the overrides: an event whose name no variant
/// of the event union has). `SseItemDecoder` emits no item for it, and the
/// stream goes on.
final class SseEventIgnored implements Exception {
  /// Creates the signal.
  const SseEventIgnored();

  @override
  String toString() => 'SseEventIgnored';
}
