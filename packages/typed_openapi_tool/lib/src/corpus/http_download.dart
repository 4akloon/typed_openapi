import 'dart:io';
import 'dart:typed_data';

import 'corpus_exception.dart';

/// Downloads a URL with `dart:io`, following redirects; only `fetch` uses
/// the network, never a test.
final class HttpDownload {
  /// Creates the download.
  const HttpDownload();

  /// The bytes at [url]; a status other than 200 is a [CorpusException].
  Future<List<int>> call(Uri url) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode != HttpStatus.ok) {
        throw CorpusException('GET $url answered ${response.statusCode}.');
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add);
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }
}
