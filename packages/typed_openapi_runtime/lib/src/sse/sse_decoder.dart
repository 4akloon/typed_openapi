import 'dart:async';
import 'dart:convert';

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
///
/// Malformed input never throws; errors of the source stream pass through.
final class SseDecoder extends StreamTransformerBase<List<int>, SseMessage> {
  /// Creates a decoder; each bound stream gets its own state.
  const SseDecoder();

  @override
  Stream<SseMessage> bind(Stream<List<int>> stream) => Stream.eventTransformed(
    // bind, not stream.transform: a Stream<Uint8List> (what Dio gives) does
    // not accept a transformer of List<int> at run time.
    const Utf8Decoder(allowMalformed: true).bind(stream),
    _SseSink.new,
  );
}

/// The parser state of one stream.
final class _SseSink implements EventSink<String> {
  _SseSink(this._out);

  final EventSink<SseMessage> _out;
  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  bool _afterCr = false;
  bool _hasData = false;
  String _eventType = '';
  String _lastEventId = '';
  Duration? _retry;

  @override
  void add(String chunk) {
    // The Utf8Decoder in bind has already stripped a leading BOM; a second
    // U+FEFF is data (it becomes part of the field name).
    var start = 0;
    for (var i = start; i < chunk.length; i++) {
      final unit = chunk.codeUnitAt(i);
      if (unit == 0x0A && _afterCr) {
        _afterCr = false;
        start = i + 1;
      } else if (unit == 0x0A || unit == 0x0D) {
        _line.write(chunk.substring(start, i));
        _endLine();
        start = i + 1;
        _afterCr = unit == 0x0D;
      } else {
        _afterCr = false;
      }
    }
    _line.write(chunk.substring(start));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() => _out.close();

  void _endLine() {
    final line = _line.toString();
    _line.clear();
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _eventType = value;
      case 'data':
        _data
          ..write(value)
          ..write('\n');
        _hasData = true;
      case 'id' when !value.contains('\u0000'):
        _lastEventId = value;
      case 'retry' when _digits.hasMatch(value):
        if (int.tryParse(value) case final millis? when millis <= _maxRetry) {
          _retry = Duration(milliseconds: millis);
        }
    }
  }

  void _dispatch() {
    if (!_hasData) {
      _eventType = '';
      return;
    }
    final data = _data.toString();
    _out.add(
      SseMessage(
        event: _eventType.isEmpty ? 'message' : _eventType,
        data: data.substring(0, data.length - 1),
        id: _lastEventId,
        retry: _retry,
      ),
    );
    _data.clear();
    _hasData = false;
    _eventType = '';
  }

  /// The most milliseconds a retry may take: a [Duration] counts microseconds,
  /// and 2^53 of them (9007199254740 ms) is the largest count JavaScript
  /// holds exactly, so the same cap applies on every platform.
  static const int _maxRetry = 9007199254740;

  static final RegExp _digits = RegExp(r'^[0-9]+$');
}
