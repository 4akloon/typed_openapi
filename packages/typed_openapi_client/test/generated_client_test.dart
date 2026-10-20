import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'helpers/fake_transport.dart';
import 'helpers/pets_api.dart';

/// A hand-written fake in another library, as a user test writes one.
class FakePetsApi implements PetsApi {
  @override
  Future<Result<Pet, ApiError>> getPetById({
    required int petId,
    List<String>? fields,
    CallOptions? call,
  }) async => Success(
    Pet(id: petId, name: 'Fake', bornAt: DateTime.utc(2020)),
    statusCode: 200,
  );

  @override
  Future<Result<void, ApiError>> updatePet({
    required int petId,
    required UpdatePet body,
    CallOptions? call,
  }) async => const HttpError(ApiError(code: 'READ_ONLY'), statusCode: 403);

  @override
  Future<Result<Stream<SseItem<PetChange>>, Never>> watchPet({
    required int petId,
    CallOptions? call,
  }) async => Success(
    Stream.fromIterable([
      const SseEvent(PetChange(name: 'Rex')),
      const SseDisconnected(),
    ]),
    statusCode: 200,
  );
}

void main() {
  const petJson = {
    'id': 7,
    'name': 'Rex',
    'bornAt': '2020-01-02T03:04:05.000Z',
    'tags': [
      {'name': 'good'},
    ],
    'metadata': {'source': 'shelter', 'score': 1.5},
    'unknown': 'ignored',
  };

  test('a generated GET decodes a model and its nested values', () async {
    final adapter = FakeTransport.json(200, petJson);
    final api = PetsApi(adapter);
    final result = await api.getPetById(petId: 7, fields: ['id', 'name']);
    final pet = switch (result) {
      Success(:final data) => data,
      Failure() => fail('expected a success, got $result'),
    };
    expect(pet.tags?.single.name, 'good');
    expect(pet.metadata['source'].asString, 'shelter');
    expect(pet.bornAt, DateTime.utc(2020, 1, 2, 3, 4, 5));
    expect(
      jsonEncode(pet.toJson()),
      '{"id":7,"name":"Rex","bornAt":"2020-01-02T03:04:05.000Z",'
      '"tags":[{"name":"good"}],"metadata":{"source":"shelter","score":1.5}}',
    );
    expect(
      adapter.requests.single.target,
      '/pets/7?fields=id,name',
    );
  });

  test('a group built with defaults merges them into every call', () async {
    final adapter = FakeTransport.json(200, petJson);
    final api = PetsApi(
      adapter,
      defaults: const CallOptions(headers: {'x-app': 'one'}),
    );
    await api.getPetById(petId: 7);
    await api.getPetById(
      petId: 7,
      call: const CallOptions(headers: {'x-call': 'two'}),
    );
    expect(adapter.requests[0].headers['x-app'], ['one']);
    expect(adapter.requests[1].headers['x-app'], ['one']);
    expect(adapter.requests[1].headers['x-call'], ['two']);
    final PetsApi mock = FakePetsApi();
    expect(mock, isA<PetsApi>());
  });

  test('a date property decodes and encodes as a full-date', () async {
    final adapter = FakeTransport.json(200, {
      ...petJson,
      'birthday': '2019-12-31',
    });
    final result = await PetsApi(adapter).getPetById(petId: 7);
    final pet = switch (result) {
      Success(:final data) => data,
      Failure() => fail('expected a success, got $result'),
    };
    expect(pet.birthday, Date(2019, 12, 31));
    expect(pet.toJson()['birthday'], '2019-12-31');
  });

  test(
    'a date-time sent for a date is a decode error at the property',
    () async {
      final adapter = FakeTransport.json(200, {
        ...petJson,
        'birthday': '2019-12-31T00:00:00Z',
      });
      final result = await PetsApi(adapter).getPetById(petId: 7);
      expect(
        result,
        isA<DecodeError<Pet, ApiError>>()
            .having((e) => e.error.pointer, 'pointer', '/birthday')
            .having((e) => e.error.schema, 'schema', 'Pet')
            .having((e) => e.error.actual, 'actual', 'a date-time')
            .having((e) => e.statusCode, 'statusCode', 200),
      );
    },
  );

  test('the caller switches over every outcome', () async {
    final adapter = FakeTransport.json(200, {
      ...petJson,
      'tags': [{}],
    });
    final result = await PetsApi(adapter).getPetById(petId: 7);
    final message = switch (result) {
      Success(:final data) => data.name,
      HttpError(:final body) => body.code,
      DecodeError(:final error) => '${error.schema} ${error.pointer}',
      UndocumentedStatus() || TransportError() || Cancelled() => 'retry',
    };
    expect(message, 'Tag /tags/0/name');
  });

  test('a generated PATCH sends only the fields that are set', () async {
    final adapter = FakeTransport((_) => FakeTransport.response('', 204));
    final result = await PetsApi(adapter).updatePet(
      petId: 7,
      body: const UpdatePet(name: .value('Rex'), tag: .nullValue()),
    );
    expect(result, isA<Success<void, ApiError>>());
    expect(adapter.bodies.single, '{"name":"Rex","tag":null}');
    expect(adapter.requests.single.method, 'PATCH');
  });

  test('a documented error status is typed', () async {
    final adapter = FakeTransport.json(409, {'code': 'CONFLICT'});
    final result = await PetsApi(
      adapter,
    ).updatePet(petId: 7, body: const UpdatePet());
    expect((result as HttpError<void, ApiError>).body.code, 'CONFLICT');
    expect(adapter.bodies.single, '{}');
  });

  test('a generated event stream yields typed items', () async {
    final adapter = FakeTransport(
      (_) => FakeTransport.response(
        'data: {"name": "Max"}\n\n',
        200,
        'text/event-stream',
      ),
    );
    final result = await PetsApi(adapter).watchPet(petId: 7);
    final names = switch (result) {
      Success(:final data) =>
        await data
            .map(
              (item) => switch (item) {
                SseEvent(:final data) => data.name,
                SseDecodeError() => 'bad event',
                SseReconnecting() => 'reconnecting',
                SseDisconnected() => 'end',
              },
            )
            .toList(),
      Failure() => ['failed'],
    };
    expect(names, ['Max', 'end']);
  });

  test('an operation without documented errors still has failures', () async {
    final adapter = FakeTransport.json(503, {'message': 'down'});
    final result = await PetsApi(adapter).watchPet(petId: 7);
    final outcome = switch (result) {
      Success() => 'stream',
      Failure() => 'failed',
    };
    expect(outcome, 'failed');
    expect(
      result,
      isA<UndocumentedStatus<Stream<SseItem<PetChange>>, Never>>().having(
        (u) => u.statusCode,
        'statusCode',
        503,
      ),
    );
  });

  // A compile-time check of R10.7: the API class can be faked through
  // `implements`.
  test('the API class is mocked with implements', () async {
    final PetsApi api = FakePetsApi();
    expect(
      await api.getPetById(petId: 3),
      isA<Success<Pet, ApiError>>().having((s) => s.data.name, 'name', 'Fake'),
    );
    expect(
      await api.updatePet(petId: 3, body: const UpdatePet()),
      isA<HttpError<void, ApiError>>(),
    );
    final watched = await api.watchPet(petId: 3);
    expect(
      await (watched as Success<Stream<SseItem<PetChange>>, Never>).data.length,
      2,
    );
  });
}
