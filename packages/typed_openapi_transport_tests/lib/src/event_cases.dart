import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of event streams: events arrive as they are written, pieces
/// that split a line or a character are joined, `retry:` sets the delay of a
/// reconnection, which sends `Last-Event-ID`, a 204 ends the stream, an
/// error status is an error, and a cancel ends the stream and the request.
final class EventCases {
  /// Creates the cases on [context].
  const EventCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase(
        'events arrive, reconnect with Last-Event-ID and end on cancel',
        _reconnect,
      )
      ..testCase('pieces that split a line and a character are joined', _split)
      ..testCase('retry sets the delay of the reconnection', _retry)
      ..testCase('a 204 ends the stream', _noContent)
      ..testCase('an error status with a body is the typed error', _error)
      ..testCase('a listener cancel closes the connection', _listenerCancel);
  }

  static Result<Stream<SseItem<String>>, String> _decodeError(
    RawResponse response,
  ) => switch (response.statusCode) {
    503 => response.error(response.jsonObject['code']! as String),
    _ => response.undocumented(),
  };

  Future<Result<Stream<SseItem<String>>, String>> _open(
    String path, {
    CallOptions? call,
    SseReconnection reconnection = .off,
  }) => context.sender.openEvents<String, String>(
    ConformanceContext.request(path, streamStatuses: {200, 204}),
    (message) => message.data,
    _decodeError,
    call: call,
    reconnection: reconnection,
  );

  Stream<SseItem<String>> _stream(
    Result<Stream<SseItem<String>>, String> result,
  ) => (result as Success<Stream<SseItem<String>>, String>).data;

  Future<void> _reconnect() async {
    final signal = CancelSignal();
    final result = await _open(
      '/events',
      call: CallOptions(
        cancel: signal,
        sse: SseOptions(reconnect: true, wait: (_) async {}),
      ),
      reconnection: .on,
    );
    final seen = <String>[];
    await for (final item in _stream(result)) {
      switch (item) {
        case SseEvent(:final data):
          seen.add(data);
          if (data != 'one') signal.cancel();
        case SseReconnecting():
          seen.add('reconnecting');
        case SseDisconnected(cause: TransportException(:final kind)):
          seen.add('end ${kind.name}');
        case _:
          seen.add('$item');
      }
    }
    expect(seen, ['one', 'reconnecting', 'after 1', 'end cancelled']);
  }

  /// The server writes a comment, then one event with an accented letter
  /// and one with an id, a byte at a time.
  Future<void> _split() async {
    final items = await _stream(await _open('/events/split')).toList();
    expect(items, hasLength(3));
    expect(
      items.take(2).map((item) => (item as SseEvent<String>).data),
      ['héllo', 'two'],
    );
    expect((items[1] as SseEvent<String>).id, '7');
    expect(items.last, isA<SseDisconnected<String>>());
  }

  Future<void> _retry() async {
    final signal = CancelSignal();
    final delays = <Duration>[];
    final result = await _open(
      '/events/retry',
      call: CallOptions(
        cancel: signal,
        sse: SseOptions(
          reconnect: true,
          wait: (delay) async => delays.add(delay),
        ),
      ),
      reconnection: .on,
    );
    final data = <String>[];
    await for (final item in _stream(result)) {
      if (item is SseEvent<String>) {
        data.add(item.data);
        if (data.length == 2) signal.cancel();
      }
    }
    expect(data, ['a', 'b 1']);
    expect(delays, [const Duration(milliseconds: 1500)]);
  }

  Future<void> _noContent() async {
    final result = await _open(
      '/events/no-content',
      call: CallOptions(sse: SseOptions(reconnect: true, wait: (_) async {})),
      reconnection: .on,
    );
    final items = await _stream(result).toList();
    expect(items.whereType<SseReconnecting<String>>(), isEmpty);
    expect(items.last, isA<SseDisconnected<String>>());
  }

  Future<void> _error() async {
    final error = await _open('/events/error');
    final failure = error as HttpError<Stream<SseItem<String>>, String>;
    expect((failure.statusCode, failure.body), (503, 'status 503'));
  }

  Future<void> _listenerCancel() async {
    final result = await _open('/events/endless');
    final first = Completer<void>();
    final subscription = _stream(result).listen(
      (item) {
        if (item is SseEvent<String> && !first.isCompleted) first.complete();
      },
    );
    await first.future;
    await subscription.cancel();
    await context.waitForServer(
      (s) => s['disconnects']!['/events/endless'] == 1,
    );
  }
}
