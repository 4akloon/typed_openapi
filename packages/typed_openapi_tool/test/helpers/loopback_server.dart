import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';

/// A loopback HTTP server for download tests; nothing leaves the machine.
final class LoopbackServer {
  const LoopbackServer._();

  /// Runs [body] against a loopback server whose requests [handler]
  /// answers.
  static Future<void> serve(
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

  /// A matcher for a [CorpusException] whose message matches [message].
  static Matcher corpusError(Object message) => throwsA(
    isA<CorpusException>().having((e) => e.message, 'message', message),
  );
}
