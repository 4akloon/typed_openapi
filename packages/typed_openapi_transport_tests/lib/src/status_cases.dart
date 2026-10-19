import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of statuses without a body or with an unusual one, and of the
/// `HEAD` method: each goes through the core and ends in the result type
/// its decoder gives.
final class StatusCases {
  /// Creates the cases on [context].
  const StatusCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a 201 is a success with its body', _created)
      ..testCase('a 204 is a success with no body', _noContent)
      ..testCase('an empty 200 body is a success with no body', _empty)
      ..testCase('a 422 is a typed error', () => _typed(422))
      ..testCase('a 500 is a typed error', () => _typed(500))
      ..testCase('a 503 is an undocumented status', _unavailable)
      ..testCase('HEAD answers the status and headers with no body', _head);
  }

  static Result<Object?, String> _decode(RawResponse r) =>
      switch (r.statusCode) {
        200 || 201 || 204 => r.success(r.body),
        422 || 500 => r.error(r.jsonObject['code']! as String),
        _ => r.undocumented(),
      };

  Future<Success<Object?, String>> _success(
    String path, {
    String method = 'GET',
  }) async {
    final result = await context.sender.send(
      ConformanceContext.request(path, method: method),
      _decode,
    );
    return result as Success<Object?, String>;
  }

  Future<void> _created() async {
    final success = await _success('/status/201');
    expect(success.statusCode, 201);
    expect(success.data, {'code': 'status 201'});
  }

  Future<void> _noContent() async {
    final success = await _success('/empty/204');
    expect((success.statusCode, success.data), (204, null));
  }

  Future<void> _empty() async {
    final success = await _success('/empty/200');
    expect((success.statusCode, success.data), (200, null));
  }

  Future<void> _typed(int code) async {
    final result = await context.sender.send(
      ConformanceContext.request('/status/$code'),
      _decode,
    );
    final error = result as HttpError<Object?, String>;
    expect((error.statusCode, error.body), (code, 'status $code'));
  }

  Future<void> _unavailable() async {
    final result = await context.sender.send(
      ConformanceContext.request('/status/503'),
      _decode,
    );
    final undocumented = result as UndocumentedStatus<Object?, String>;
    expect(undocumented.statusCode, 503);
    expect(undocumented.rawBody, {'code': 'status 503'});
  }

  Future<void> _head() async {
    final success = await _success('/echo', method: 'HEAD');
    expect((success.statusCode, success.data), (200, null));
    expect(success.headers['x-answer'], ['echoed']);
  }
}
