import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  final options = RequestOptions(path: '/pets');
  final failures = <Failure<int, String>>[
    const HttpError('not found', statusCode: 404),
    const UndocumentedStatus(statusCode: 418, rawBody: 'teapot'),
    DecodeError(
      JsonDecodeException(
        expected: 'an integer',
        actual: 'a string',
        path: ['id'],
        schema: 'Pet',
      ),
      statusCode: 200,
      rawBody: {'id': 'x'},
    ),
    TransportError(
      DioException.connectionError(requestOptions: options, reason: 'refused'),
      StackTrace.empty,
    ),
    Cancelled(
      DioException.requestCancelled(requestOptions: options, reason: 'left'),
      StackTrace.empty,
    ),
  ];

  String describe(Result<int, String> result) => switch (result) {
    Success(:final data) => 'ok $data',
    HttpError(:final statusCode, :final body) => '$statusCode $body',
    UndocumentedStatus(:final statusCode) => 'undocumented $statusCode',
    DecodeError(:final error) => 'decode ${error.pointer}',
    TransportError(:final exception) => 'transport ${exception.type.name}',
    Cancelled() => 'cancelled',
  };

  test('an exhaustive switch reads every outcome', () {
    const Result<int, String> ok = Success(
      7,
      statusCode: 200,
      headers: {
        'etag': ['"1"'],
      },
    );
    expect(describe(ok), 'ok 7');
    expect(failures.map(describe), [
      '404 not found',
      'undocumented 418',
      'decode /id',
      'transport connectionError',
      'cancelled',
    ]);
  });

  test('a success describes itself by its status, not its data', () {
    expect(
      '${const Success<String, Never>('private', statusCode: 201)}',
      'Success(201)',
    );
  });

  test('failures describe themselves', () {
    expect(failures.map((f) => '$f'), [
      'HttpError(404)',
      'UndocumentedStatus(418)',
      'DecodeError(200: JsonDecodeException: expected an integer, '
          'got a string at /id in Pet)',
      'TransportError(connectionError)',
      'Cancelled',
    ]);
  });

  test('E = Never and T = void type-check', () {
    const Result<void, Never> done = Success(null, statusCode: 204);
    const Result<void, Never> other = UndocumentedStatus(statusCode: 500);
    expect(done, isA<Success<void, Never>>());
    expect(switch (other) {
      Success() => 'ok',
      UndocumentedStatus(:final statusCode) => '$statusCode',
      Failure() => 'failure',
    }, '500');
  });
}
