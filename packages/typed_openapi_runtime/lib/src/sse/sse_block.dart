import 'sse_message.dart';

/// One block of an event stream, the lines up to an empty line, and what it
/// leaves behind.
///
/// WHATWG sets the last event id at every empty line, also when the block has
/// no `data` and so dispatches no event: `id: 9` followed by an empty line
/// moves the id a reconnection sends.
final class SseBlock {
  /// Creates the block that ended with the state [lastEventId] and [retry].
  const SseBlock({required this.lastEventId, this.retry, this.message});

  /// The event the block dispatches, or null when it has no `data`.
  final SseMessage? message;

  /// The last event id of the stream after the block; `''` when there is
  /// none.
  final String lastEventId;

  /// The last valid `retry` of the stream after the block, or null.
  final Duration? retry;
}
