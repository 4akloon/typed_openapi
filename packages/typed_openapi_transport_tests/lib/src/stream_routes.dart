import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server_stats.dart';

/// The routes that answer in pieces or never finish: a large chunked body,
/// a slow one, a closed socket, and the event streams.
final class StreamRoutes {
  /// Creates the routes that record into [stats].
  const StreamRoutes(this.stats);

  /// Where a client that goes away is counted.
  final ServerStats stats;

  /// The size of the body `/large-stream` writes.
  static const largeLength = 4 * 1024 * 1024;

  /// The size of each chunk of `/large-stream`.
  static const chunkLength = 64 * 1024;

  /// How long a held-back route waits before it gives up.
  static const _patience = Duration(seconds: 5);

  /// The byte at [index] of the large body.
  static int largeByte(int index) => index % 251;

  /// Answers nothing for a while: not even the headers.
  Future<void> slow(HttpRequest request) async {
    await Future<void>.delayed(_patience);
    await request.response.close();
  }

  /// Drops the connection without an answer.
  Future<void> closeSocket(HttpRequest request) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.destroy();
  }

  /// Writes [largeLength] bytes in chunks of [chunkLength], with no
  /// `Content-Length`, so the body is chunked.
  Future<void> largeStream(HttpRequest request) async {
    final response = request.response
      ..bufferOutput = false
      ..headers.contentType = ContentType.binary;
    for (var start = 0; start < largeLength; start += chunkLength) {
      response.add([
        for (var i = start; i < start + chunkLength; i++) largeByte(i),
      ]);
      await response.flush();
    }
    await response.close();
  }

  /// Writes the first bytes, then one byte every so often until the client
  /// goes away.
  Future<void> trickle(HttpRequest request) async {
    await _holdOpen(request, 'text/plain', utf8.encode('first'), [0x2e]);
  }

  /// Events for the event-stream cases, by the last segment of the path.
  Future<void> events(HttpRequest request, String? kind) async {
    final response = request.response
      ..bufferOutput = false
      ..headers.contentType = ContentType('text', 'event-stream');
    final lastId = request.headers.value('last-event-id');
    switch (kind) {
      case null:
        await _reconnecting(response, lastId, 'id: 1\ndata: one\n\n', 'after');
      case 'retry':
        await _reconnecting(
          response,
          lastId,
          'retry: 1500\nid: 1\ndata: a\n\n',
          'b',
        );
      case 'split':
        await _split(response);
      case 'no-content':
        response.statusCode = 204;
        await response.close();
      case 'error':
        response
          ..statusCode = 503
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'code': 'status 503'}));
        await response.close();
      case 'endless':
        final tick = utf8.encode('data: tick\n\n');
        await _holdOpen(request, 'text/event-stream', tick, tick);
      default:
        response.statusCode = 404;
        await response.close();
    }
  }

  /// Without `Last-Event-ID`: [first], then the connection closes. With it:
  /// one event that names the id, then the connection stays open until the
  /// client leaves.
  Future<void> _reconnecting(
    HttpResponse response,
    String? lastId,
    String first,
    String after,
  ) async {
    if (lastId == null) {
      response.write(first);
      await response.close();
      return;
    }
    response.write('data: $after $lastId\n\n');
    await response.flush();
  }

  /// A comment, an event with a multi-byte character and an event with an
  /// id, each byte in a piece of its own, so the pieces split lines and the
  /// UTF-8 sequence of the letter e with an acute accent.
  Future<void> _split(HttpResponse response) async {
    final bytes = utf8.encode(': ping\n\ndata: héllo\n\nid: 7\ndata: two\n\n');
    for (final byte in bytes) {
      response.add([byte]);
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await response.close();
  }

  /// Answers `200` with [contentType], writes [first], then [piece] every
  /// 20 ms until the client goes away, which counts a disconnect (gives up
  /// after the patience).
  ///
  /// The response is written on the detached socket: `dart:io` does not
  /// tell a handler that the client left, but the socket's end does.
  Future<void> _holdOpen(
    HttpRequest request,
    String contentType,
    List<int> first,
    List<int> piece,
  ) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    var gone = false;
    socket.listen(
      (_) {},
      onDone: () => gone = true,
      onError: (Object _) => gone = true,
      cancelOnError: true,
    );
    socket.write(
      'HTTP/1.1 200 OK\r\ncontent-type: $contentType\r\n'
      'access-control-allow-origin: *\r\n'
      'access-control-expose-headers: *\r\n'
      'transfer-encoding: chunked\r\n\r\n',
    );
    var chunk = first;
    final stopAt = DateTime.now().add(_patience);
    while (!gone && DateTime.now().isBefore(stopAt)) {
      try {
        socket
          ..write('${chunk.length.toRadixString(16)}\r\n')
          ..add(chunk)
          ..write('\r\n');
        await socket.flush();
      } on Exception {
        gone = true;
      }
      chunk = piece;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (gone) stats.disconnect(request.uri.path);
    socket.destroy();
  }
}
