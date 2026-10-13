import '../ir/ir.dart';
import 'dart_writer.dart';
import 'decoder_writer.dart';

/// Writes what a method that returns events adds to the M9 shape (R12.1,
/// R12.5): the statuses that open the stream, the decoder of one event's
/// data, how the stream reconnects and a doc paragraph about it.
final class EventStreamWriter {
  /// Creates a writer that decodes JSON with [_decoder].
  const EventStreamWriter(this._decoder);

  final DecoderWriter _decoder;

  /// Writes the `streamStatuses` of the request of [operation]: its 2xx
  /// statuses, a range as every code in it.
  void statuses(DartWriter out, OperationIr operation) {
    final codes = [
      for (final response in operation.successes)
        if (int.tryParse(response.status) case final code?) '$code',
    ];
    final hasRange = operation.successes.any(
      (response) => int.tryParse(response.status) == null,
    );
    // A range holds every code of it, so the codes are not listed again.
    final elements = hasRange ? ['for (var s = 200; s < 300; s++) s'] : codes;
    out.line('streamStatuses: {${elements.join(', ')}},');
  }

  /// The function that decodes the data of one event of [events].
  String decoder(EventStreamIr events) => switch ((events.union, events.data)) {
    (final union?, _) => '${union.name}.fromEvent',
    (null, null) => '(m) => m.data',
    (null, final data?) => '(m) => ${_decoder.decode(data, 'm.json')}',
  };

  /// Writes the named arguments after `call` of `openEvents`.
  void reconnection(DartWriter out, EventStreamIr events) {
    if (events.reconnection == .onRequest) return;
    out.line('reconnection: .${events.reconnection.name},');
  }

  /// The doc paragraph of a method that returns [events] with the HTTP
  /// [method]: a GET that does not reconnect has an override that says so,
  /// any other method does not unless the override enables it.
  String doc(EventStreamIr events, {required String method}) {
    final reconnect = switch (events.reconnection) {
      .off when method == 'GET' =>
        "It does not reconnect: the operation's `sse.reconnect` override "
            'turns it off.',
      .off =>
        "It does not reconnect unless the operation's `sse.reconnect` "
            'override enables it.',
      .onRequest =>
        'It reconnects with `Last-Event-ID` when `call.sse` asks for it.',
      .on => 'It reconnects with `Last-Event-ID` unless `call.sse` says no.',
    };
    return 'Returns the events of `text/event-stream` as they arrive; the '
        'stream ends with `SseDisconnected`. $reconnect';
  }
}
