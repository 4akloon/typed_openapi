/// Behaviour that exists only in a browser, run with
/// `dart test -p chrome` (dart2js) and
/// `dart test -p chrome --compiler dart2wasm`, with no simulated platform.
@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'helpers/fake_adapter.dart';

void main() {
  const getPet = OperationInfo(
    operationId: 'getPet',
    method: 'GET',
    pathTemplate: '/pets/{petId}',
  );
  const request = OperationRequest(
    getPet,
    path: [PathParameter('petId', 7)],
  );

  Result<Object?, Never> decode(RawResponse r) => switch (r.statusCode) {
    200 => r.success(r.json),
    _ => r.undocumented(),
  };

  Future<Result<Object?, Never>> send(
    FakeAdapter adapter, {
    OperationRequest operation = request,
  }) => ClientSender(
    DioTransport(
      Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter,
    ),
  ).send(operation, decode);

  test('the platform is detected without configuration', () {
    expect(DioTransport(Dio()).isWeb, isTrue);
  });

  test('the default Dio adapter cannot stream events and says so', () async {
    final result = await ClientSender(DioTransport(Dio()))
        .openEvents<String, Never>(
          const OperationRequest(
            getPet,
            path: [PathParameter('petId', 7)],
            streamStatuses: {200},
          ),
          (message) => message.data,
          (response) => response.undocumented(),
        );
    final error = result as TransportError<Stream<SseItem<String>>, Never>;
    expect(error.exception.message, DioTransport.webStreamingMessage);
    expect(error.exception.cause, isA<UnsupportedError>());
  });

  test(
    'a reconnecting stream on the default adapter fails the same way',
    () async {
      var waits = 0;
      final result = await ClientSender(DioTransport(Dio()))
          .openEvents<String, Never>(
            const OperationRequest(
              getPet,
              path: [PathParameter('petId', 7)],
              streamStatuses: {200},
            ),
            (message) => message.data,
            (response) => response.undocumented(),
            call: CallOptions(
              sse: SseOptions(reconnect: true, wait: (_) async => waits++),
            ),
            reconnection: SseReconnection.on,
          );
      final error = result as TransportError<Stream<SseItem<String>>, Never>;
      expect(error.exception.message, DioTransport.webStreamingMessage);
      expect(waits, 0);
    },
  );

  group('malformed JSON', () {
    // The client parses the bytes itself, so every compiler reports the
    // same: the status and the text.
    for (final body in ['{"id":', '<html>', '{"id": 7}x']) {
      test('$body is a decode error with its status and text', () async {
        final result = await send(
          FakeAdapter.text(200, body, 'application/json'),
        );
        final error = result as DecodeError<Object?, Never>;
        expect(error.statusCode, 200);
        expect(error.error.pointer, '');
        expect(
          error.error.message,
          'expected a JSON body, got text that is not JSON',
        );
        expect(error.rawBody, body);
      });
    }

    test('a text operation never reads JSON, so a failure is transport', () {
      final adapter = FakeAdapter((_) => throw const FormatException('x'));
      return expectLater(
        send(
          adapter,
          operation: const OperationRequest(
            getPet,
            path: [PathParameter('petId', 7)],
            responseKind: .text,
          ),
        ),
        completion(isA<TransportError<Object?, Never>>()),
      );
    });
  });

  test('a FormatException from an interceptor is a transport failure, never '
      'a decode error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = FakeAdapter.json(200, {'id': 7})
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            Uri.parse('http://[bad');
          },
        ),
      );
    final result = await ClientSender(DioTransport(dio)).send(request, decode);
    expect(result, isA<TransportError<Object?, Never>>());
  });

  test('valid JSON and an empty body are not decode errors', () async {
    final ok = await send(
      FakeAdapter.json(200, {'id': 7, 'name': 'Rex'}),
    );
    expect((ok as Success<Object?, Never>).data, {'id': 7, 'name': 'Rex'});
    final empty = await send(FakeAdapter.text(200, '', 'application/json'));
    expect((empty as Success<Object?, Never>).data, isNull);
  });
}
