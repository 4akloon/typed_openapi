import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of the response as the client reads it: statuses, headers,
/// bytes and receive progress.
final class ResponseCases {
  /// Creates the cases on [context].
  const ResponseCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a documented error status is typed', _error)
      ..testCase('an undocumented status keeps its body', _undocumented)
      ..testCase('the response headers arrive', _headers)
      ..testCase('a binary body arrives as it was sent', _bytes)
      ..testCase('receive progress counts to the content length', _progress);
  }

  static Result<Object?, String> _decode(RawResponse r) =>
      switch (r.statusCode) {
        200 => r.success(r.body),
        404 => r.error(r.jsonObject['code']! as String),
        _ => r.undocumented(),
      };

  Future<void> _error() async {
    final result = await context.sender.send(
      ConformanceContext.request('/status/404'),
      _decode,
    );
    final error = result as HttpError<Object?, String>;
    expect((error.statusCode, error.body), (404, 'status 404'));
  }

  Future<void> _undocumented() async {
    final result = await context.sender.send(
      ConformanceContext.request('/status/418'),
      _decode,
    );
    final undocumented = result as UndocumentedStatus<Object?, String>;
    expect(undocumented.statusCode, 418);
    expect(undocumented.rawBody, {'code': 'status 418'});
  }

  Future<void> _headers() async {
    final result = await context.sender.send(
      ConformanceContext.request('/echo'),
      ConformanceContext.echo,
    );
    final success = result as Success<Map<String, Object?>, Never>;
    expect(success.headers['x-answer'], ['echoed']);
    expect(
      success.headers['content-type']?.single,
      startsWith('application/json'),
    );
  }

  Future<void> _bytes() async {
    final result = await context.sender.send(
      ConformanceContext.request('/bytes', responseKind: .bytes),
      _decode,
    );
    expect((result as Success<Object?, String>).data, [0, 1, 2, 254, 255]);
  }

  Future<void> _progress() async {
    final counts = <(int, int)>[];
    final result = await context.sender.send(
      ConformanceContext.request('/large', responseKind: .text),
      _decode,
      call: CallOptions(
        onReceiveProgress: (received, total) {
          counts.add((received, total));
        },
      ),
    );
    expect(
      ((result as Success<Object?, String>).data! as String).length,
      100000,
    );
    expect(counts.last, (100000, 100000));
  }
}
