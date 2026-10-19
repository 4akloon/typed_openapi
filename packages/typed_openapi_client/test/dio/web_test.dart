/// Behaviour that exists only in a browser, run with
/// `dart test -p chrome` (dart2js) and
/// `dart test -p chrome --compiler dart2wasm`, with no simulated platform.
@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/test_platform.dart';

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
  }) => DioRequestSender(
    Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter,
  ).send(operation, decode);

  test('the platform is detected without configuration', () {
    expect(DioRequestSender(Dio()).isWeb, isTrue);
  });

  test('the default Dio adapter cannot stream events and says so', () async {
    final result = await DioRequestSender(Dio()).openEvents<String, Never>(
      const OperationRequest(
        getPet,
        path: [PathParameter('petId', 7)],
        streamStatuses: {200},
      ),
      (message) => message.data,
      (response) => response.undocumented(),
    );
    final error = result as TransportError<Stream<SseItem<String>>, Never>;
    expect(error.exception.message, DioRequestSender.webStreamingMessage);
    expect(error.exception.error, isA<UnsupportedError>());
  });

  test(
    'a reconnecting stream on the default adapter fails the same way',
    () async {
      var waits = 0;
      final result = await DioRequestSender(Dio()).openEvents<String, Never>(
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
      expect(error.exception.message, DioRequestSender.webStreamingMessage);
      expect(waits, 0);
    },
  );

  group('malformed JSON', () {
    // What Dio's JSON parser reports differs by compiler: dart2js gives the
    // browser's SyntaxError text with no source, dart2wasm the body bytes.
    for (final body in ['{"id":', '<html>', '{"id": 7}x']) {
      test('$body is a decode error without a status', () async {
        final result = await send(
          FakeAdapter.text(200, body, 'application/json'),
        );
        final error = result as DecodeError<Object?, Never>;
        expect(error.statusCode, isNull);
        expect(error.error.pointer, '');
        expect(
          error.error.message,
          'expected a JSON body, got text that is not JSON',
        );
        expect(error.rawBody, TestPlatform.isJavaScript ? isNull : body);
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

  test('a FormatException from an interceptor of a JSON request is a decode '
      'error too, because the failures cannot be told apart', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = FakeAdapter.json(200, {'id': 7})
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            Uri.parse('http://[bad');
          },
        ),
      );
    final result = await DioRequestSender(dio).send(request, decode);
    expect(result, isA<DecodeError<Object?, Never>>());
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
