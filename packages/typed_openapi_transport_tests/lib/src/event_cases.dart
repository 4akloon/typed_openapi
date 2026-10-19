import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of event streams: events arrive as they are written, a
/// reconnection sends `Last-Event-ID`, a cancel ends the stream.
final class EventCases {
  /// Creates the cases on [context].
  const EventCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context.testCase(
      'events arrive, reconnect with Last-Event-ID and end on cancel',
      _reconnect,
    );
  }

  Future<void> _reconnect() async {
    final signal = CancelSignal();
    final result = await context.sender.openEvents<String, Never>(
      ConformanceContext.request('/events', streamStatuses: {200}),
      (message) => message.data,
      (response) => response.undocumented(),
      call: CallOptions(
        cancel: signal,
        sse: SseOptions(reconnect: true, wait: (_) async {}),
      ),
      reconnection: .on,
    );
    final seen = <String>[];
    final items = (result as Success<Stream<SseItem<String>>, Never>).data;
    await for (final item in items) {
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
}
