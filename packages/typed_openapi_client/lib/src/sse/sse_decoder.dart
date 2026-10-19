import 'dart:async';

import 'sse_block_decoder.dart';
import 'sse_message.dart';

/// Decodes a `text/event-stream` body into [SseMessage]s, following the
/// WHATWG HTML "Interpreting an event stream" rules. Generated code uses
/// it through `SseItemDecoder`.
///
/// - Bytes are UTF-8 (invalid sequences become U+FFFD, a leading BOM is
///   dropped); a character split between chunks is kept whole.
/// - Lines end with CRLF, LF or CR, also when CR and LF arrive in different
///   chunks.
/// - `event`, `data` (several lines joined by `\n`), `id` (ignored when it
///   contains U+0000) and `retry` (ASCII digits only, otherwise ignored);
///   lines starting with `:` are comments; other fields are ignored.
/// - An empty line dispatches the event unless no `data` was seen; an event
///   not finished by an empty line when the stream ends is discarded.
///   A block without `data` dispatches no event, but its `id` and `retry`
///   still count: `SseItemDecoder` reads them from `SseBlockDecoder`.
///
/// Malformed input never throws; errors of the source stream pass through.
final class SseDecoder extends StreamTransformerBase<List<int>, SseMessage> {
  /// Creates a decoder; each bound stream gets its own state, which starts
  /// from [lastEventId] and [retry].
  const SseDecoder({this.lastEventId = '', this.retry});

  /// The last event id before the stream starts: a reconnection carries the
  /// id of the connection before it, as an `EventSource` does.
  final String lastEventId;

  /// The reconnection time before the stream starts.
  final Duration? retry;

  @override
  Stream<SseMessage> bind(Stream<List<int>> stream) => SseBlockDecoder(
    lastEventId: lastEventId,
    retry: retry,
  ).bind(stream).expand((block) => [?block.message]);
}
