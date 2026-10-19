import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The loopback HTTP server the conformance cases call: it echoes requests,
/// answers with a status, bytes or a large body, holds a request back, and
/// streams server-sent events. It runs on the VM, in the test's own process
/// or, for a browser test, in a hybrid isolate (`server_main.dart`).
final class ConformanceServer {
  ConformanceServer._(this._server, this.closedPort);

  /// Starts the server on `127.0.0.1` and an ephemeral port.
  static Future<ConformanceServer> start() async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = closed.port;
    await closed.close();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return ConformanceServer._(server, closedPort).._listen();
  }

  final HttpServer _server;

  /// A port nothing listens on, for the connection-refused case.
  final int closedPort;

  /// The port the server listens on.
  int get port => _server.port;

  /// Stops the server and drops its open connections.
  Future<void> close() => _server.close(force: true);

  void _listen() => _server.listen((request) async {
    final response = request.response;
    // Browsers call from another origin: allow every method and header,
    // and let the client read the headers the cases check.
    response.headers
      ..set('access-control-allow-origin', '*')
      ..set('access-control-allow-methods', '*')
      ..set('access-control-allow-headers', '*')
      ..set('access-control-expose-headers', '*');
    if (request.method == 'OPTIONS') return response.close();
    final segments = request.uri.pathSegments;
    switch (segments) {
      case ['echo', ...]:
        await _echo(request);
      case ['status', final code]:
        response.statusCode = int.parse(code);
        _json(response, {'code': 'status $code'});
        await response.close();
      case ['bytes']:
        response.headers.contentType = ContentType.binary;
        response.add([0, 1, 2, 254, 255]);
        await response.close();
      case ['large']:
        final body = List<int>.filled(100000, 0x61);
        response.headers
          ..contentType = ContentType.text
          ..contentLength = body.length;
        response.add(body);
        await response.close();
      case ['slow']:
        await Future<void>.delayed(const Duration(seconds: 5));
        await response.close();
      case ['events']:
        await _events(request);
      default:
        response.statusCode = 404;
        await response.close();
    }
  });

  static Future<void> _echo(HttpRequest request) async {
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    request.response.headers.set('x-answer', 'echoed');
    _json(request.response, {
      'method': request.method,
      'target': '${request.uri}',
      'headers': headers,
      'body': utf8.decode(body, allowMalformed: true),
      'length': body.length,
    });
    await request.response.close();
  }

  /// Without `Last-Event-ID`: an event with id `1`, then the connection
  /// closes. With it: one event that names the id, then the connection
  /// stays open until the client leaves.
  static Future<void> _events(HttpRequest request) async {
    final response = request.response
      // Unbuffered, so each event leaves when it is written.
      ..bufferOutput = false
      ..headers.contentType = ContentType('text', 'event-stream');
    final lastId = request.headers.value('last-event-id');
    if (lastId == null) {
      response.write('id: 1\ndata: one\n\n');
      await response.close();
      return;
    }
    response.write('data: after $lastId\n\n');
    await response.flush();
  }

  static void _json(HttpResponse response, Object? body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}
