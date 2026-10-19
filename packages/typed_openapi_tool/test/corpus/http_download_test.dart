@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/http_download.dart';

import '../helpers/loopback_server.dart';

void main() {
  test('returns the bytes of a 200 answer', () async {
    await LoopbackServer.serve(
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
    await LoopbackServer.serve(
      (request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      },
      (url) => expectLater(
        const HttpDownload()(url),
        LoopbackServer.corpusError(contains('answered 404')),
      ),
    );
  });

  test('a refused connection is a CorpusException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = Uri.parse('http://127.0.0.1:${server.port}/spec.yaml');
    await server.close(force: true);
    await expectLater(
      const HttpDownload()(url),
      LoopbackServer.corpusError(
        allOf(contains('$url'), contains('could not be fetched')),
      ),
    );
  });

  test('a URL without a host is a CorpusException', () async {
    await expectLater(
      const HttpDownload()(Uri.parse('http:///spec.yaml')),
      LoopbackServer.corpusError(contains('no host')),
    );
  });

  test('a server that never answers times out as a CorpusException', () async {
    await LoopbackServer.serve(
      (request) async {},
      (url) => expectLater(
        const HttpDownload(
          totalTimeout: Duration(milliseconds: 200),
        )(url),
        LoopbackServer.corpusError(contains('timed out')),
      ),
    );
  });

  test('a body that stalls half way times out as a CorpusException', () async {
    await LoopbackServer.serve(
      (request) async {
        request.response.contentLength = 100;
        request.response.write('partial');
        await request.response.flush();
      },
      (url) => expectLater(
        const HttpDownload(
          totalTimeout: Duration(milliseconds: 300),
        )(url),
        LoopbackServer.corpusError(contains('timed out')),
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
        LoopbackServer.corpusError(contains('could not be fetched')),
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
      LoopbackServer.corpusError(contains('could not be fetched')),
    );
  });

  test('a URL that is not http or https is a CorpusException', () async {
    for (final url in ['ftp://example.com/a.yaml', 'file:///etc/passwd', 'x']) {
      await expectLater(
        const HttpDownload()(Uri.parse(url)),
        LoopbackServer.corpusError(contains('only http and https')),
        reason: url,
      );
    }
  });

  group('the size cap', () {
    const cap = 1000;

    test('a body over the cap without Content-Length is aborted', () async {
      await LoopbackServer.serve(
        (request) async {
          request.response.headers.chunkedTransferEncoding = true;
          for (var i = 0; i < 5; i++) {
            request.response.add(List.filled(400, 0x61));
            await request.response.flush();
          }
          await request.response.close();
        },
        (url) => expectLater(
          const HttpDownload(maxBytes: cap)(url),
          LoopbackServer.corpusError(contains('larger than $cap bytes')),
        ),
      );
    });

    test(
      'a body that Content-Length announces over the cap is refused',
      () async {
        await LoopbackServer.serve(
          (request) async {
            request.response.contentLength = cap + 1;
            request.response.add(List.filled(10, 0x61));
            await request.response.flush();
          },
          (url) => expectLater(
            const HttpDownload(maxBytes: cap)(url),
            LoopbackServer.corpusError(contains('larger than $cap bytes')),
          ),
        );
      },
    );

    test('a body of exactly the cap succeeds', () async {
      await LoopbackServer.serve(
        (request) async {
          request.response.add(List.filled(cap, 0x61));
          await request.response.close();
        },
        (url) async {
          expect(await const HttpDownload(maxBytes: cap)(url), hasLength(cap));
        },
      );
    });
  });
}
