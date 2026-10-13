@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/http_download.dart';

/// Runs [body] against a loopback server whose requests [handler] answers;
/// nothing leaves the machine.
Future<void> _serve(
  Future<void> Function(HttpRequest request) handler,
  Future<void> Function(Uri base) body,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  try {
    await body(Uri.parse('http://127.0.0.1:${server.port}/spec.yaml'));
  } finally {
    await server.close(force: true);
  }
}

Matcher _corpusError(Object message) => throwsA(
  isA<CorpusException>().having((e) => e.message, 'message', message),
);

void main() {
  test('returns the bytes of a 200 answer', () async {
    await _serve(
      (request) async {
        request.response.write('openapi: 3.1.0');
        await request.response.close();
      },
      (url) async {
        expect(utf8.decode(await const HttpDownload()(url)), 'openapi: 3.1.0');
      },
    );
  });

  test('another status is a CorpusException', () async {
    await _serve(
      (request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      },
      (url) => expectLater(
        const HttpDownload()(url),
        _corpusError(contains('answered 404')),
      ),
    );
  });

  test('a refused connection is a CorpusException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = Uri.parse('http://127.0.0.1:${server.port}/spec.yaml');
    await server.close(force: true);
    await expectLater(
      const HttpDownload()(url),
      _corpusError(allOf(contains('$url'), contains('could not be fetched'))),
    );
  });

  test('a host that does not exist is a CorpusException', () async {
    await expectLater(
      const HttpDownload()(Uri.parse('http://nonexistent.invalid/spec.yaml')),
      _corpusError(contains('could not be fetched')),
    );
  });

  test('a server that never answers times out as a CorpusException', () async {
    await _serve(
      (request) async {},
      (url) => expectLater(
        const HttpDownload(
          totalTimeout: Duration(milliseconds: 200),
        )(url),
        _corpusError(contains('timed out')),
      ),
    );
  });

  test('a body that stalls half way times out as a CorpusException', () async {
    await _serve(
      (request) async {
        request.response.contentLength = 100;
        request.response.write('partial');
        await request.response.flush();
      },
      (url) => expectLater(
        const HttpDownload(
          totalTimeout: Duration(milliseconds: 300),
        )(url),
        _corpusError(contains('timed out')),
      ),
    );
  });

  test(
    'a connection closed in the middle of a body is a CorpusException',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) async {
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort');
        await socket.flush();
        await socket.close();
      });
      addTearDown(server.close);
      await expectLater(
        const HttpDownload()(
          Uri.parse('http://127.0.0.1:${server.port}/spec.yaml'),
        ),
        _corpusError(contains('could not be fetched')),
      );
    },
  );

  test('a TLS failure is a CorpusException', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      socket
        ..write('not a TLS handshake\r\n')
        ..destroy();
    });
    addTearDown(server.close);
    await expectLater(
      const HttpDownload()(
        Uri.parse('https://127.0.0.1:${server.port}/spec.yaml'),
      ),
      _corpusError(contains('could not be fetched')),
    );
  });

  test('a URL that is not http or https is a CorpusException', () async {
    for (final url in ['ftp://example.com/a.yaml', 'file:///etc/passwd', 'x']) {
      await expectLater(
        const HttpDownload()(Uri.parse(url)),
        _corpusError(contains('only http and https')),
        reason: url,
      );
    }
  });
}
