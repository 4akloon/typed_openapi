import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'corpus_exception.dart';

/// Downloads a URL with `dart:io`, following redirects; only `fetch` uses
/// the network, never a test.
///
/// Every failure of the network is a [CorpusException], so a command reports
/// it and exits `1` instead of crashing.
final class HttpDownload {
  /// Creates the download; connecting takes at most [connectionTimeout] and
  /// the whole download at most [totalTimeout].
  const HttpDownload({
    this.connectionTimeout = const Duration(seconds: 30),
    this.totalTimeout = const Duration(minutes: 5),
    this.maxBytes = defaultMaxBytes,
  });

  /// The default size cap, 256 MiB: the pinned archives and specs are far
  /// smaller (the largest spec file is 13 MB), so this only stops a runaway
  /// answer from filling the memory.
  static const int defaultMaxBytes = 256 * 1024 * 1024;

  /// How long a connection may take to open.
  final Duration connectionTimeout;

  /// How long the answer may take, from the request to the last byte.
  final Duration totalTimeout;

  /// The most bytes a download may have; the read stops as soon as the
  /// running total passes it.
  final int maxBytes;

  /// The bytes at [url]; a status other than 200, a network failure, a
  /// timeout or a body over [maxBytes] is a [CorpusException].
  Future<List<int>> call(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw CorpusException('GET $url: only http and https are fetched.');
    }
    if (url.host.isEmpty) {
      throw CorpusException('GET $url: the URL has no host.');
    }
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      return await _get(client, url, maxBytes).timeout(totalTimeout);
    } on TimeoutException {
      throw CorpusException(
        'GET $url timed out after ${totalTimeout.inSeconds} s.',
      );
    } on SocketException catch (e) {
      throw _failed(url, e.message);
    } on TlsException catch (e) {
      throw _failed(url, e.message);
    } on HttpException catch (e) {
      throw _failed(url, e.message);
    } finally {
      // Force: a stalled body must not keep the process alive.
      client.close(force: true);
    }
  }

  static CorpusException _failed(Uri url, String reason) =>
      CorpusException('GET $url could not be fetched: $reason');

  static CorpusException _tooLarge(Uri url, int maxBytes) =>
      CorpusException('GET $url is larger than $maxBytes bytes.');

  static Future<List<int>> _get(
    HttpClient client,
    Uri url,
    int maxBytes,
  ) async {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw CorpusException('GET $url answered ${response.statusCode}.');
    }
    if (response.contentLength > maxBytes) throw _tooLarge(url, maxBytes);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      // Leaving the loop cancels the subscription and so the read.
      if (bytes.length > maxBytes) throw _tooLarge(url, maxBytes);
    }
    return bytes.takeBytes();
  }
}
