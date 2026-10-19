import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'helpers/fake_adapter.dart';

void main() {
  const json = {
    'content-type': ['application/json'],
  };
  const info = OperationInfo(
    operationId: 'getPet',
    method: 'GET',
    pathTemplate: '/pets',
  );

  Future<Result<Object?, Never>> sendResolved(
    Object? data, {
    Map<String, List<String>> headers = json,
    Result<Object?, Never> Function(RawResponse)? decode,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = FakeAdapter.json(500, null)
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: data,
              headers: Headers.fromMap(headers),
            ),
          ),
        ),
      );
    return ClientSender(DioTransport(dio)).send(
      const OperationRequest(info),
      decode ?? (r) => r.success(r.json),
    );
  }

  test('a map resolved by an interceptor reaches the client as JSON', () async {
    final result = await sendResolved({'cached': true});
    expect((result as Success<Object?, Never>).data, {'cached': true});
  });

  test(
    'a list resolved by an interceptor reaches the client as JSON',
    () async {
      final result = await sendResolved([
        {'id': 1},
      ]);
      expect((result as Success<Object?, Never>).data, [
        {'id': 1},
      ]);
    },
  );

  test('a string resolved by an interceptor is sent as UTF-8', () async {
    final result = await sendResolved(
      '{"id":1}',
      decode: (r) => r.success(r.json),
    );
    expect((result as Success<Object?, Never>).data, {'id': 1});
  });

  test('bytes resolved by an interceptor are one chunk', () async {
    final result = await sendResolved(
      Uint8List.fromList([123, 125]),
      decode: (r) => r.success(r.json),
    );
    expect((result as Success<Object?, Never>).data, <String, Object?>{});
  });

  test('null resolved by an interceptor is an empty body', () async {
    final result = await sendResolved(
      null,
      headers: {},
      decode: (r) => r.success(r.text),
    );
    expect((result as Success<Object?, Never>).data, '');
  });

  test('an unsupported object is a transport failure of kind other', () async {
    final result = await sendResolved(Object());
    final failure = result as TransportError<Object?, Never>;
    expect(failure.exception.kind, TransportExceptionKind.other);
    expect(failure.exception.message, contains('Object'));
  });

  test('a mixed-case Content-Type header is read as JSON', () async {
    final result = await sendResolved(
      '{"id":1}',
      headers: {
        'Content-Type': ['application/json'],
      },
    );
    expect((result as Success<Object?, Never>).data, {'id': 1});
  });
}
