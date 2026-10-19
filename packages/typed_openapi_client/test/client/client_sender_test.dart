import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

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

  test('a documented success decodes the body', () async {
    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
    final result = await ClientSender(adapter).send(request, decodePet);
    final success = result as Success<Pet, Problem>;
    expect((success.data.id, success.data.name), (7, 'Rex'));
    expect(success.statusCode, 200);
    expect(success.headers['content-type'], ['application/json']);
    final sent = adapter.requests.single;
    expect(sent.target, '/pets/7?fields=id,name');
    expect(sent.method, 'GET');
    expect(sent.operation, getPet);
  });

  test('per-call headers win over header parameters', () async {
    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
    await ClientSender(adapter).send(
      request,
      decodePet,
      call: const CallOptions(headers: {'X-Trace': 'call'}),
    );
    expect(FakeTransport.header(adapter.requests.single, 'X-Trace'), 'call');
  });

  test('a documented error status is typed', () async {
    final adapter = FakeTransport.json(404, {'code': 'gone'});
    final result = await ClientSender(adapter).send(request, decodePet);
    final error = result as HttpError<Pet, Problem>;
    expect((error.statusCode, error.body.code), (404, 'gone'));
  });

  test('a documented error body that does not decode', () async {
    final adapter = FakeTransport.json(404, {'message': 'gone'});
    final result = await ClientSender(adapter).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, 404);
    expect(error.rawBody, {'message': 'gone'});
    expect((error.error.schema, error.error.pointer), ('Problem', '/code'));
  });

  test('an undocumented status keeps the raw body', () async {
    final adapter = FakeTransport.json(418, {'tea': true});
    final result = await ClientSender(adapter).send(request, decodePet);
    final undocumented = result as UndocumentedStatus<Pet, Problem>;
    expect(undocumented.statusCode, 418);
    expect(undocumented.rawBody, {'tea': true});
  });

  test('a body that does not match the schema is a decode error', () async {
    final adapter = FakeTransport.json(200, {'id': 'seven', 'name': 'Rex'});
    final result = await ClientSender(adapter).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, 200);
    expect(error.error.pointer, '/id');
    expect(error.error.message, 'expected an integer, got a string');
    expect(error.error.schema, 'Pet');
    expect(error.rawBody, {'id': 'seven', 'name': 'Rex'});
  });

  test('malformed JSON is a decode error with its status', () async {
    final broken = FakeTransport.text(200, '{"id": 7,', 'application/json');
    final result = await ClientSender(broken).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.statusCode, 200);
    expect(
      error.error.message,
      'expected a JSON body, got text that is not JSON',
    );
    expect(error.rawBody, '{"id": 7,');
  });

  test('JSON sent as text/plain is not guessed', () async {
    final adapter = FakeTransport.text(
      200,
      '{"id": 7, "name": "Rex"}',
      'text/plain',
    );
    final result = await ClientSender(adapter).send(request, decodePet);
    final error = result as DecodeError<Pet, Problem>;
    expect(error.error.message, 'expected an object, got a string');
    expect(error.rawBody, '{"id": 7, "name": "Rex"}');
  });

  test('transport failures keep the TransportException', () async {
    for (final kind in [
      TransportExceptionKind.connection,
      TransportExceptionKind.timeout,
      TransportExceptionKind.other,
    ]) {
      final failure = TransportException(kind, 'failed', cause: 'adapter');
      final adapter = FakeTransport((_) => throw failure);
      final result = await ClientSender(adapter).send(request, decodePet);
      final error = result as TransportError<Pet, Problem>;
      expect(error.exception, same(failure));
    }
  });

  test('an Exception while the body is read is a transport failure', () async {
    final adapter = FakeTransport(
      (_) => TransportResponse(
        statusCode: 200,
        body: Stream.error(const FormatException('broken')),
      ),
    );
    final result = await ClientSender(adapter).send(request, decodePet);
    final error = result as TransportError<Pet, Problem>;
    expect(error.exception.kind, TransportExceptionKind.other);
    expect(error.exception.cause, isA<FormatException>());
  });

  test('header entries with a null value are not sent', () async {
    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
    await ClientSender(adapter).send(
      request,
      decodePet,
      call: const CallOptions(headers: {'X-A': null, 'X-B': 'b'}),
    );
    final sent = adapter.requests.single;
    expect(FakeTransport.header(sent, 'X-A'), isNull);
    expect(FakeTransport.header(sent, 'X-B'), 'b');
  });

  test(
    'the operation content type wins over one in CallOptions.headers',
    () async {
      final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
      await ClientSender(adapter).send(
        const OperationRequest(
          getPet,
          path: [PathParameter('petId', 7)],
          body: {'name': 'Rex'},
          contentType: 'application/json',
        ),
        decodePet,
        call: const CallOptions(
          headers: {'content-type': 'application/merge-patch+json', 'X-A': 'a'},
        ),
      );
      final sent = adapter.requests.single;
      expect(FakeTransport.header(sent, 'content-type'), 'application/json');
      expect(FakeTransport.header(sent, 'X-A'), 'a');
    },
  );

  test('cancellation is its own outcome', () async {
    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
    final token = CancelSignal()..cancel('user left');
    final result = await ClientSender(adapter).send(
      request,
      decodePet,
      call: CallOptions(cancel: token),
    );
    expect(
      (result as Cancelled<Pet, Problem>).exception.kind,
      TransportExceptionKind.cancelled,
    );
    expect(adapter.requests, isEmpty);
  });

  test('bodies, content types, progress and response kinds', () async {
    final adapter = FakeTransport.text(201, 'created', 'text/plain');
    final sent = <int>[];
    final result = await ClientSender(adapter).send(
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
    expect(
      FakeTransport.header(adapter.requests.single, 'content-type'),
      'application/json',
    );
    expect(sent, [25]);

    final bytes = FakeTransport(
      (_) => TransportResponse(
        statusCode: 200,
        body: Stream.value([1, 2, 3]),
        headers: {
          'content-type': ['application/octet-stream'],
        },
      ),
    );
    final download = await ClientSender(bytes).send(
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
    final adapter = FakeTransport((_) => FakeTransport.response('', 204));
    final result = await ClientSender(adapter).send(
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
        final adapter = FakeTransport.json(status, body);
        final result = await ClientSender(adapter).send(request, decode);
        final error = result as DecodeError<DateTime, Problem>;
        expect(error.statusCode, status);
        expect(error.rawBody, body);
        expect(error.error.pointer, '');
        expect(error.error.expected, 'a value its decoder accepts');
        expect(error.error.actual, startsWith('a value it rejected: '));
        expect(error.headers, isNotEmpty);
      }
      final valid = await ClientSender(
        FakeTransport.json(200, '2024-02-03T04:05:06Z'),
      ).send(request, decode);
      expect((valid as Success<DateTime, Problem>).data.year, 2024);
    },
  );

  test('an Error of the decoder still reaches the caller', () async {
    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
    final sender = ClientSender(adapter);
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
