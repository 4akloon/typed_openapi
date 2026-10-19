import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of redirects. Whether a redirect is followed is the
/// transport's policy, not the core's; these cases document what a
/// transport that follows them (`DioTransport` with Dio's default) does:
/// the result is the final response, so the `Location` target answers.
///
/// A transport that does not follow redirects skips them with that reason.
final class RedirectCases {
  /// Creates the cases on [context].
  const RedirectCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a 301 is followed to the Location target', () => _follow(301))
      ..testCase(
        'a 302 is followed to the Location target',
        () => _follow(302),
      );
  }

  Future<void> _follow(int code) async {
    final result = await context.sender.send(
      ConformanceContext.request('/redirect/$code'),
      ConformanceContext.echo,
    );
    final success = result as Success<Map<String, Object?>, Never>;
    expect(success.data['method'], 'GET');
    expect(success.data['target'], '/echo/redirected');
  }
}
