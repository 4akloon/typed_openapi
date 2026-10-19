import 'dart:async';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'helpers/fake_adapter.dart';

/// A documented error body.
final class Problem {
  const Problem(this.code);

  factory Problem.fromJson(Map<String, Object?> json) => Problem(
    JsonReader(json, schema: 'Problem').required('code', JsonReader.asString),
  );

  final String code;
}

void main() {
  const getPet = OperationInfo(
    operationId: 'getPet',
    method: 'GET',
    pathTemplate: '/pets/{petId}',
    tags: ['pets'],
  );
  const request = OperationRequest(
    getPet,
    path: [PathParameter('petId', 7)],
    headers: [HeaderParameter('X-Trace', 't1')],
  );

  Result<Object?, Problem> decode(RawResponse r) => switch (r.statusCode) {
    200 => r.success(r.json),
    404 => r.error(Problem.fromJson(r.jsonObject)),
    _ => r.undocumented(),
  };

  Dio dioWith(HttpClientAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
        ..httpClientAdapter = adapter;

  Future<Result<Object?, Problem>> send(
    Dio dio, {
    OperationRequest operation = request,
    CallOptions? call,
  }) => ClientSender(DioTransport(dio)).send(operation, decode, call: call);

  test('the request reaches Dio with its path, headers and metadata', () async {
    final adapter = FakeAdapter.json(200, {'id': 7});
    final result = await send(dioWith(adapter));
    expect((result as Success<Object?, Problem>).data, {'id': 7});
    final sent = adapter.requests.single;
    expect(sent.uri.toString(), 'https://api.test/v1/pets/7');
    expect((sent.method, sent.headers['X-Trace']), ('GET', 't1'));
    expect(DioTransport.operationOf(sent), getPet);
    expect(DioTransport.operationOf(RequestOptions()), isNull);
  });

  test('the query keeps // under a base URL (allowReserved)', () async {
    final adapter = FakeAdapter.json(200, null);
    await send(
      dioWith(adapter),
      operation: const OperationRequest(
        getPet,
        path: [PathParameter('petId', 7)],
        query: [QueryParameter('next', '/a//b', allowReserved: true)],
      ),
    );
    expect(
      adapter.requests.single.uri.toString(),
      'https://api.test/v1/pets/7?next=/a//b',
    );
  });

  test('the Dio instance is used as it is and never changed', () async {
    final dio = dioWith(FakeAdapter.json(200, null));
    final before = (dio.options.headers.length, dio.interceptors.length);
    await send(dio, call: const CallOptions(headers: {'X-Call': '1'}));
    expect((dio.options.headers.length, dio.interceptors.length), before);
  });

  test('an error status passes onError first, then is typed', () async {
    final seen = <int?>[];
    final dio = dioWith(FakeAdapter.json(404, {'code': 'gone'}))
      ..interceptors.add(
        InterceptorsWrapper(
          onError: (e, handler) {
            seen.add(e.response?.statusCode);
            handler.next(e);
          },
        ),
      );
    final result = await send(dio);
    expect((result as HttpError<Object?, Problem>).body.code, 'gone');
    expect(seen, [404]);
  });

  test('a validateStatus that accepts errors gives the same result', () async {
    final dio = dioWith(FakeAdapter.json(404, {'code': 'gone'}))
      ..options.validateStatus = (_) => true;
    final result = await send(dio);
    expect((result as HttpError<Object?, Problem>).statusCode, 404);
  });

  test('a response resolved by an interceptor is read as a stream', () async {
    final dio = dioWith(FakeAdapter.json(500, null))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody.fromString(
                '{"id":1}',
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ),
              headers: Headers.fromMap({
                Headers.contentTypeHeader: ['application/json'],
              }),
            ),
          ),
        ),
      );
    final result = await send(dio);
    expect((result as Success<Object?, Problem>).data, {'id': 1});
  });

  test('a connection error is a transport failure with its cause', () async {
    final dio = dioWith(FakeAdapter.json(200, null))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException.connectionError(
              requestOptions: options,
              reason: 'refused',
            ),
          ),
        ),
      );
    final result = await send(dio);
    final failure = result as TransportError<Object?, Problem>;
    expect(failure.exception.kind, TransportExceptionKind.connection);
    expect(failure.exception.cause, isA<DioException>());
  });

  test('a timeout is a transport failure of kind timeout', () async {
    final dio = dioWith(FakeAdapter.json(200, null))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException.receiveTimeout(
              timeout: const Duration(seconds: 1),
              requestOptions: options,
            ),
          ),
        ),
      );
    final result = await send(dio);
    final failure = result as TransportError<Object?, Problem>;
    expect(failure.exception.kind, TransportExceptionKind.timeout);
  });

  test('an Error thrown in an interceptor is rethrown', () async {
    final dio = dioWith(FakeAdapter.json(200, null))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => throw StateError('bug'),
        ),
      );
    await expectLater(send(dio), throwsStateError);
  });

  test('a cancel signal cancels the Dio request', () async {
    final signal = CancelSignal();
    final adapter = FakeAdapter((_) {
      signal.cancel('stop');
      return ResponseBody.fromString('', 200);
    });
    final result = await send(
      dioWith(adapter),
      call: CallOptions(cancel: signal),
    );
    expect(result, isA<Cancelled<Object?, Problem>>());
  });
}
