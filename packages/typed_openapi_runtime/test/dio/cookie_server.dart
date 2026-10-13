// A local HTTP server for `cookie_browser_test.dart`, started in the VM by
// `spawnHybridUri`: it answers every request with the `Cookie` and
// `X-Probe` headers it received, and allows any origin (CORS), so a page
// in Chrome can call it. It listens on the loopback only; no external
// network is used.
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// Starts the server and sends its port on [channel].
Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final response = request.response;
    response.headers
      ..set(
        'Access-Control-Allow-Origin',
        request.headers.value('origin') ?? '*',
      )
      ..set('Access-Control-Allow-Credentials', 'true')
      ..set(
        'Access-Control-Allow-Headers',
        request.headers.value('access-control-request-headers') ?? '*',
      );
    if (request.method == 'OPTIONS') {
      response.close();
      return;
    }
    response
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'cookie': request.headers.value('cookie'),
          'probe': request.headers.value('x-probe'),
        }),
      )
      ..close();
  });
  channel.sink.add(server.port);
}
