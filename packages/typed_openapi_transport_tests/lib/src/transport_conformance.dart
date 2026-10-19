import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';
import 'event_cases.dart';
import 'failure_cases.dart';
import 'multipart_cases.dart';
import 'redirect_cases.dart';
import 'request_cases.dart';
import 'response_cases.dart';
import 'status_cases.dart';
import 'streaming_cases.dart';

/// The cases every [ClientTransport] runs against the loopback
/// `ConformanceServer`: the request on the wire, the response as the
/// client reads it, failures, cancellation, progress and event streams.
///
/// A transport package calls [register] from a test file:
///
/// ```dart
/// void main() => TransportConformance(
///   (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
/// ).register();
/// ```
final class TransportConformance {
  /// Creates the suite for the transports [create] makes for a base URL.
  /// [createWithTimeout] makes a transport that gives up on a request after
  /// the duration it is given; without it the timeout case is skipped.
  /// [skips] maps a case name to the reason the transport does not meet
  /// it on this platform; a name that is not a case fails the test
  /// `every skip names a case`.
  TransportConformance(
    this.create, {
    this.createWithTimeout,
    this.skips = const {},
  });

  /// Makes the transport under test for the server's base URL.
  final ClientTransport Function(Uri baseUrl) create;

  /// Makes the transport with a connect and receive timeout, or null.
  final ClientTransport Function(Uri baseUrl, Duration timeout)?
  createWithTimeout;

  /// The cases skipped, by name, with the reason.
  final Map<String, String> skips;

  /// Declares the cases as tests, with a server started once for them.
  void register() {
    final context = ConformanceContext(create, createWithTimeout, skips);
    setUpAll(context.start);
    tearDownAll(context.stop);
    group('requests', () => RequestCases(context).register());
    group('multipart', () => MultipartCases(context).register());
    group('responses', () => ResponseCases(context).register());
    group('statuses', () => StatusCases(context).register());
    group('redirects', () => RedirectCases(context).register());
    group('streaming', () => StreamingCases(context).register());
    group('failures', () => FailureCases(context).register());
    group('events', () => EventCases(context).register());
    test('every skip names a case', context.checkSkips);
  }
}
