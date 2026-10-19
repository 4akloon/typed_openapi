import 'package:stream_channel/stream_channel.dart';

import 'conformance_server.dart';

/// Starts a [ConformanceServer] for `spawnHybridUri` and sends its port and
/// a closed port; the server stops when the test closes the channel.
///
/// `package:test` calls this top-level function by its name, so it cannot
/// be a method.
Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await ConformanceServer.start();
  channel.sink.add([server.port, server.closedPort]);
  await channel.stream.drain<void>();
  await server.close();
}
