import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/test_platform.dart';

/// A model the way generated code reads one.
final class Pet {
  const Pet(this.id, this.name);

  factory Pet.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Pet');
    return Pet(
      r.required('id', JsonReader.asInt),
      r.required('name', JsonReader.asString),
    );
  }

  final int id;
  final String name;
}

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
    query: [
      QueryParameter('fields', ['id', 'name'], explode: false),
    ],
    headers: [HeaderParameter('X-Trace', 't1')],
  );

  // The decoder a generated method passes: 200 is Pet, 404 is Problem.
  Result<Pet, Problem> decodePet(RawResponse r) => switch (r.statusCode) {
    200 => r.success(Pet.fromJson(r.jsonObject)),
    404 => r.error(Problem.fromJson(r.jsonObject)),
    _ => r.undocumented(),
  };

  Dio dioWith(FakeAdapter adapter, {BaseOptions? options}) =>
      Dio(options ?? BaseOptions(baseUrl: 'https://api.test/v1'))
        ..httpClientAdapter = adapter;

  test('the query keeps // under a base URL (allowReserved)', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    final seen = <String>[];
    final dio = dioWith(adapter);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, handler) {
          seen.add(o.uri.toString());
          handler.next(o);
        },
      ),
    );
    await DioRequestSender(dio).send(
      const OperationRequest(
        getPet,
        path: [PathParameter('petId', 7)],
        query: [QueryParameter('next', '/a//b', allowReserved: true)],
      ),
      decodePet,
    );
    const expected = 'https://api.test/v1/pets/7?next=/a//b';
    expect(seen, [expected]);
    expect(adapter.requests.single.uri.toString(), expected);
    expect(adapter.requests.single.queryParameters, isEmpty);
  });

  test('a documented success decodes the body', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    final result = await DioRequestSender(
      dioWith(adapter),
    ).send(request, decodePet);
    final success = result as Success<Pet, Problem>;
    expect((success.data.id, success.data.name), (7, 'Rex'));
    expect(success.statusCode, 200);
    expect(success.headers['content-type'], ['application/json']);
    final sent = adapter.requests.single;
    expect(sent.uri.toString(), 'https://api.test/v1/pets/7?fields=id,name');
    expect(sent.queryParameters, isEmpty);
  });

  test('the Dio instance is used as is and never changed', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    final dio = dioWith(
      adapter,
      options: BaseOptions(
        baseUrl: 'https://api.test',
        headers: {'Authorization': 'Bearer x', 'X-Trace': 'base'},
        extra: {'base': true},
      ),
    );
    final interceptor = InterceptorsWrapper();
    dio.interceptors.add(interceptor);
    final validateStatus = dio.options.validateStatus;
    await DioRequestSender(dio).send(
      request,
      decodePet,
      call: const CallOptions(headers: {'X-Call': 'c'}, extra: {'call': 1}),
    );
    final sent = adapter.requests.single;
    expect(sent.headers['Authorization'], 'Bearer x');
    expect(sent.headers['X-Trace'], 't1');
    expect(sent.headers['X-Call'], 'c');
    expect(sent.extra['base'], isTrue);
    expect(sent.extra['call'], 1);
    expect(OperationInfo.of(sent), getPet);
    expect(dio.options.baseUrl, 'https://api.test');
    expect(dio.options.headers, {
      'Authorization': 'Bearer x',
      'X-Trace': 'base',
    });
    expect(dio.options.extra, {'base': true});
    expect(dio.options.validateStatus, same(validateStatus));
    expect(dio.interceptors.whereType<InterceptorsWrapper>(), [interceptor]);
  });

  test('per-call headers win over header parameters', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    await DioRequestSender(dioWith(adapter)).send(
      request,
      decodePet,
      call: const CallOptions(headers: {'X-Trace': 'call'}),
    );
    expect(adapter.requests.single.headers['X-Trace'], 'call');
  });

  test('an error status passes onError first, then is typed', () async {
    final adapter = FakeAdapter.json(404, {'code': 'NOT_FOUND'});
    final dio = dioWith(adapter);
    final seen = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          seen.add(
            '${e.type.name} ${e.response?.statusCode} '
            '${OperationInfo.of(e.requestOptions)?.operationId}',
          );
          handler.next(e);
        },
      ),
    );
    final result = await DioRequestSender(dio).send(request, decodePet);
    expect(seen, ['badResponse 404 getPet']);
    final error = result as HttpError<Pet, Problem>;
    expect((error.statusCode, error.body.code), (404, 'NOT_FOUND'));
  });

  test('a documented error body that does not decode', () async {
    final adapter = FakeAdapter.json(404, {'message': 'gone'});
    final result = await DioRequestSender(
      dioWith(adapter),
    ).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, 404);
    expect(error.rawBody, {'message': 'gone'});
    expect((error.error.schema, error.error.pointer), ('Problem', '/code'));
  });

  test('an undocumented status keeps the raw body', () async {
    final adapter = FakeAdapter.json(418, {'tea': true});
    final result = await DioRequestSender(
      dioWith(adapter),
    ).send(request, decodePet);
    final undocumented = result as UndocumentedStatus<Pet, Problem>;
    expect(undocumented.statusCode, 418);
    expect(undocumented.rawBody, {'tea': true});
  });

  test('a response resolved by an interceptor is still switched on', () async {
    final adapter = FakeAdapter.json(500, {'code': 'DOWN'});
    final dio = dioWith(adapter);
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) => handler.resolve(
          Response(requestOptions: e.requestOptions, statusCode: 503),
        ),
      ),
    );
    final result = await DioRequestSender(dio).send(request, decodePet);
    expect((result as UndocumentedStatus).statusCode, 503);
  });

  test(
    'a validateStatus that accepts everything still gives typed errors',
    () async {
      final adapter = FakeAdapter.json(404, {'code': 'NOT_FOUND'});
      final dio = dioWith(
        adapter,
        options: BaseOptions(validateStatus: (_) => true),
      );
      final result = await DioRequestSender(dio).send(request, decodePet);
      expect((result as HttpError<Pet, Problem>).body.code, 'NOT_FOUND');
    },
  );

  test('a body that does not match the schema is a decode error', () async {
    final adapter = FakeAdapter.json(200, {'id': 'seven', 'name': 'Rex'});
    final result = await DioRequestSender(
      dioWith(adapter),
    ).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, 200);
    expect(error.error.pointer, '/id');
    expect(error.error.message, 'expected an integer, got a string');
    expect(error.error.schema, 'Pet');
    expect(error.rawBody, {'id': 'seven', 'name': 'Rex'});
  });

  // Dio's JSON parser reports a failure differently in a browser (I1);
  // the browser behaviour is tested in test/dio/web_test.dart.
  test('malformed JSON is a decode error without a status', () async {
    final broken = FakeAdapter.text(200, '{"id": 7,', 'application/json');
    final result = await DioRequestSender(
      dioWith(broken),
    ).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, isNull);
    expect(
      error.error.message,
      'expected a JSON body, got text that is not JSON',
    );
    expect(error.rawBody, '{"id": 7,');
  }, testOn: 'vm');

  test('JSON sent as text/plain is not guessed', () async {
    final adapter = FakeAdapter.text(
      200,
      '{"id": 7, "name": "Rex"}',
      'text/plain',
    );
    final result = await DioRequestSender(
      dioWith(adapter),
    ).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.error.message, 'expected an object, got a string');
    expect(error.rawBody, '{"id": 7, "name": "Rex"}');
  });

  test('transport failures keep the DioException', () async {
    final cases = {
      DioExceptionType.connectionError: (RequestOptions o) =>
          DioException.connectionError(requestOptions: o, reason: 'refused'),
      DioExceptionType.receiveTimeout: (RequestOptions o) =>
          DioException.receiveTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: o,
          ),
      DioExceptionType.unknown: (RequestOptions o) =>
          DioException(requestOptions: o, error: Exception('adapter')),
    };
    for (final MapEntry(key: type, value: failure) in cases.entries) {
      final adapter = FakeAdapter((o) => throw failure(o));
      final result = await DioRequestSender(
        dioWith(adapter),
      ).send(request, decodePet);
      final error = result as TransportError<Pet, Problem>;
      expect(error.exception.type, type);
      expect(OperationInfo.of(error.exception.requestOptions), getPet);
    }
  });

  test('an Error thrown in an interceptor or adapter is rethrown', () async {
    final onRequest = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'})
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) =>
              handler.next((1 as Object) as RequestOptions),
        ),
      );
    await expectLater(
      DioRequestSender(onRequest).send(request, decodePet),
      throwsA(isA<TypeError>()),
    );
    final adapter = FakeAdapter((_) => throw StateError('adapter'));
    await expectLater(
      DioRequestSender(dioWith(adapter)).send(request, decodePet),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'off the web a FormatException that is not a JSON parse failure is '
    'transport',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'})
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              Uri.parse('http://[bad');
            },
          ),
        );
      final result = await DioRequestSender(
        dio,
        isWeb: false,
      ).send(request, decodePet);
      final error = result as TransportError<Pet, Problem>;
      expect(error.exception.error, isA<FormatException>());
    },
  );

  test(
    'a text operation never reads JSON, so a FormatException is transport',
    () async {
      for (final isWeb in [true, false]) {
        final text = FakeAdapter(
          (_) => throw const FormatException('x', [123]),
        );
        final result = await DioRequestSender(dioWith(text), isWeb: isWeb).send(
          const OperationRequest(
            getPet,
            path: [PathParameter('petId', 1)],
            responseKind: .text,
          ),
          (r) => r.undocumented<Pet, Problem>(),
        );
        expect(result, isA<TransportError<Pet, Problem>>());
      }
    },
  );

  test(
    'a FormatException of a JSON request is a decode error: any source on the '
    'web, the bytes of the body elsewhere',
    () async {
      Future<Result<Pet, Problem>> run(Object? source, {required bool isWeb}) {
        final adapter = FakeAdapter(
          (_) => throw FormatException('bad', source),
        );
        return DioRequestSender(
          dioWith(adapter),
          isWeb: isWeb,
        ).send(request, decodePet);
      }

      final bytes = Uint8List.fromList('{"id": 7,'.codeUnits);
      for (final (source, rawBody) in <(Object?, Object?)>[
        ('{"id": 7,', '{"id": 7,'),
        (null, null),
        (bytes, '{"id": 7,'),
      ]) {
        final web = await run(source, isWeb: true) as DecodeError<Pet, Problem>;
        expect(web.statusCode, isNull);
        expect(web.rawBody, rawBody);
        expect(web.error.pointer, '');
      }
      final fromBytes = await run(bytes, isWeb: false);
      expect((fromBytes as DecodeError<Pet, Problem>).rawBody, '{"id": 7,');
      for (final source in ['{"id": 7,', null]) {
        expect(
          await run(source, isWeb: false),
          isA<TransportError<Pet, Problem>>(),
        );
      }
    },
  );

  test('header entries with a null value are not sent', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    await DioRequestSender(dioWith(adapter)).send(
      request,
      decodePet,
      call: const CallOptions(headers: {'X-A': null, 'X-B': 'b'}),
    );
    final headers = adapter.requests.single.headers;
    expect(headers.containsKey('X-A'), isFalse);
    expect(headers['X-B'], 'b');
  });

  test('cancellation is its own outcome', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    final token = CancelToken()..cancel('user left');
    final result = await DioRequestSender(dioWith(adapter)).send(
      request,
      decodePet,
      call: CallOptions(cancelToken: token),
    );
    expect(
      (result as Cancelled<Pet, Problem>).exception.type,
      DioExceptionType.cancel,
    );
    expect(adapter.requests, isEmpty);
  });

  test('bodies, content types, progress and response kinds', () async {
    final adapter = FakeAdapter.text(201, 'created', 'text/plain');
    final sent = <int>[];
    final result = await DioRequestSender(dioWith(adapter)).send(
      const OperationRequest(
        OperationInfo(
          operationId: 'addPet',
          method: 'POST',
          pathTemplate: '/pets',
        ),
        body: {'name': 'Rex', 'tag': null},
        contentType: 'application/json',
        responseKind: .text,
      ),
      (r) => r.statusCode == 201
          ? r.success<String, Never>(r.text)
          : r.undocumented(),
      call: CallOptions(onSendProgress: (count, _) => sent.add(count)),
    );
    expect((result as Success<String, Never>).data, 'created');
    expect(adapter.bodies.single, '{"name":"Rex","tag":null}');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.contentType, 'application/json');
    // The adapter reports progress only when Dio streams the body to it,
    // which it does on the VM.
    if (!TestPlatform.isWeb) expect(sent, isNotEmpty);

    final bytes = FakeAdapter(
      (_) => ResponseBody.fromBytes(
        [1, 2, 3],
        200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      ),
    );
    final download = await DioRequestSender(dioWith(bytes)).send(
      const OperationRequest(
        getPet,
        path: [PathParameter('petId', 1)],
        responseKind: .bytes,
      ),
      (r) => r.success<Uint8List, Never>(r.bytes),
    );
    expect((download as Success<Uint8List, Never>).data, [1, 2, 3]);
  });

  test('a success without a body has T = void', () async {
    final adapter = FakeAdapter((_) => ResponseBody.fromString('', 204));
    final result = await DioRequestSender(dioWith(adapter)).send(
      const OperationRequest(
        OperationInfo(
          operationId: 'deletePet',
          method: 'DELETE',
          pathTemplate: '/pets/1',
        ),
      ),
      (r) =>
          r.statusCode == 204 ? r.success<void, Never>(null) : r.undocumented(),
    );
    expect(result, isA<Success<void, Never>>());
  });

  test(
    'a FormatException of the decoder is a decode error at the root',
    () async {
      // A user converter (R6.8) or Date.parse rejecting server data.
      Result<DateTime, Problem> decode(RawResponse r) => switch (r.statusCode) {
        200 => r.success(DateTime.parse(JsonReader.asString(r.json))),
        404 => r.error(
          Problem(int.parse(JsonReader.asString(r.json)).toString()),
        ),
        _ => r.undocumented(),
      };
      for (final (status, body) in [(200, 'soon'), (404, 'abc')]) {
        final adapter = FakeAdapter.json(status, body);
        final result = await DioRequestSender(
          dioWith(adapter),
        ).send(request, decode);
        final error = result as DecodeError<DateTime, Problem>;
        expect(error.statusCode, status);
        expect(error.rawBody, body);
        expect(error.error.pointer, '');
        expect(error.error.expected, 'a value its decoder accepts');
        expect(error.error.actual, startsWith('a value it rejected: '));
        expect(error.headers, isNotEmpty);
      }
      final valid = await DioRequestSender(
        dioWith(FakeAdapter.json(200, '2024-02-03T04:05:06Z')),
      ).send(request, decode);
      expect((valid as Success<DateTime, Problem>).data.year, 2024);
    },
  );

  test('an Error of the decoder still reaches the caller', () async {
    final adapter = FakeAdapter.json(200, {'id': 7, 'name': 'Rex'});
    final sender = DioRequestSender(dioWith(adapter));
    await expectLater(
      sender.send<Pet, Problem>(request, (_) => throw StateError('bug')),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      sender.send<Pet, Problem>(request, (_) => throw ArgumentError('bug')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
