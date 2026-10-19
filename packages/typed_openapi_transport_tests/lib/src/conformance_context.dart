import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

/// What the cases share: the running server, the transport under test and
/// the skips.
final class ConformanceContext {
  /// Creates the context for the transports [_create] makes, and
  /// [_createWithTimeout] for the cases that need a short timeout.
  ConformanceContext(this._create, this._createWithTimeout, this._skips);

  /// The boundary of every multipart body the senders write.
  static const boundary = 'testboundary';

  final ClientTransport Function(Uri baseUrl) _create;
  final ClientTransport Function(Uri baseUrl, Duration timeout)?
  _createWithTimeout;
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
  ClientSender get sender =>
      ClientSender(_create(_baseUrl), boundary: () => boundary);

  /// Whether the suite got a way to make a transport with a timeout.
  bool get hasTimeoutTransport => _createWithTimeout != null;

  /// A sender through a transport that gives up after [timeout]; only when
  /// [hasTimeoutTransport].
  ClientSender senderWithTimeout(Duration timeout) =>
      ClientSender(_createWithTimeout!(_baseUrl, timeout));

  /// A sender through a transport for a port nothing listens on.
  ClientSender get refusedSender =>
      ClientSender(_create(_baseUrl.replace(port: _closedPort)));

  /// Declares the case [name] as a test, skipped when the transport says
  /// so, or for the [unavailable] reason when the suite lacks what the case
  /// needs.
  void testCase(
    String name,
    Future<void> Function() body, {
    String? unavailable,
  }) {
    _names.add(name);
    test(name, body, skip: _skips[name] ?? unavailable);
  }

  /// What the server counted: `requests` and `disconnects` by path.
  Future<Map<String, Map<String, int>>> stats() async {
    final result = await sender.send(request('/stats'), echo);
    final json = (result as Success<Map<String, Object?>, Never>).data;
    return {
      for (final key in ['requests', 'disconnects'])
        key: {
          for (final MapEntry(:key, :value)
              in (json[key]! as Map<String, Object?>).entries)
            key: (value! as num).toInt(),
        },
    };
  }

  /// Asks the server until [counted] holds for what it counted, so a case
  /// waits for the server's own signal and not for a fixed time.
  Future<void> waitForServer(
    bool Function(Map<String, Map<String, int>> stats) counted,
  ) async {
    final stopAt = DateTime.now().add(const Duration(seconds: 10));
    while (!counted(await stats())) {
      if (DateTime.now().isAfter(stopAt)) fail('The server never saw it.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
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
