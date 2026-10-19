import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

/// What the cases share: the running server, the transport under test and
/// the skips.
final class ConformanceContext {
  /// Creates the context for the transports [_create] makes.
  ConformanceContext(this._create, this._skips);

  final ClientTransport Function(Uri baseUrl) _create;
  final Map<String, String> _skips;
  final Set<String> _names = {};

  // Set by [start], which `setUpAll` runs before any case reads them.
  late StreamChannel<Object?> _channel;
  late Uri _baseUrl;
  late int _closedPort;

  /// Starts the server in a hybrid isolate (the VM, also for a browser
  /// test) and waits for its ports.
  Future<void> start() async {
    _channel = spawnHybridUri(
      'package:typed_openapi_transport_tests/src/server_main.dart',
    );
    // Under dart2wasm a number from the hybrid isolate arrives as a double.
    final [port as num, closed as num] =
        await _channel.stream.first as List<Object?>;
    _baseUrl = Uri.parse('http://127.0.0.1:${port.toInt()}');
    _closedPort = closed.toInt();
  }

  /// Stops the server.
  Future<void> stop() => _channel.sink.close();

  /// A sender through a new transport for the server.
  ClientSender get sender => ClientSender(_create(_baseUrl));

  /// A sender through a transport for a port nothing listens on.
  ClientSender get refusedSender =>
      ClientSender(_create(_baseUrl.replace(port: _closedPort)));

  /// Declares the case [name] as a test, skipped when the transport says
  /// so.
  void testCase(String name, Future<void> Function() body) {
    _names.add(name);
    test(name, body, skip: _skips[name]);
  }

  /// Fails when a skip names no case: a renamed case must not stay skipped.
  void checkSkips() =>
      expect(_skips.keys.where((name) => !_names.contains(name)), isEmpty);

  /// The JSON object an `/echo` request answers with.
  static Result<Map<String, Object?>, Never> echo(RawResponse response) =>
      switch (response.statusCode) {
        200 => response.success(response.jsonObject),
        _ => response.undocumented(),
      };

  /// A request of [method] to [target] (path and query), with [body].
  static OperationRequest request(
    String target, {
    String method = 'GET',
    List<QueryParameter> query = const [],
    List<HeaderParameter> headers = const [],
    Object? body,
    String? contentType,
    ResponseKind responseKind = .json,
    Set<int> streamStatuses = const {},
  }) => OperationRequest(
    OperationInfo(
      operationId: 'conformance',
      method: method,
      pathTemplate: target,
    ),
    query: query,
    headers: headers,
    body: body,
    contentType: contentType,
    responseKind: responseKind,
    streamStatuses: streamStatuses,
  );
}
