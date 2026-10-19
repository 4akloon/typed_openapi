import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

void main() {
  const operation = OperationInfo(
    operationId: 'send',
    method: 'POST',
    pathTemplate: '/things',
  );

  Result<void, Never> decodeVoid(RawResponse r) =>
      r.statusCode == 204 ? r.success(null) : r.undocumented();

  /// Sends [body] as [contentType] and returns the adapter that saw it.
  Future<FakeTransport> send(Object? body, String? contentType) async {
    final adapter = FakeTransport(
      (_) => FakeTransport.response('', 204),
    );
    await ClientSender(adapter).send(
      OperationRequest(operation, body: body, contentType: contentType),
      decodeVoid,
    );
    return adapter;
  }

  group('a JSON body is sent as JSON text, whatever its value', () {
    for (final (name, value) in <(String, Object?)>[
      ('a string with quotes', 'hello "q"'),
      ('a string that looks like a number', '42'),
      ('an empty string', ''),
      ('an integer', 42),
      ('a number', 3.5),
      ('true', true),
      ('false', false),
      ('a list', [1, 'a', null]),
      ('an empty list', <Object?>[]),
      (
        'a map',
        {
          'k': [1, 2],
          'n': null,
        },
      ),
      ('a JsonValue string', const JsonValue('x"y')),
      ('a JsonValue map', const JsonValue({'a': 1})),
    ]) {
      test(name, () async {
        final adapter = await send(value, 'application/json');
        expect(adapter.bodies.single, jsonEncode(value));
        expect(
          FakeTransport.header(adapter.requests.single, 'content-type'),
          'application/json',
        );
      });
    }

    test('a required nullable body that is null sends null', () async {
      final adapter = await send(null, 'application/json');
      expect(adapter.bodies.single, 'null');
      expect(
        FakeTransport.header(adapter.requests.single, 'content-type'),
        'application/json',
      );
    });

    test('a +json media type is JSON as well', () async {
      final adapter = await send(
        'merge "me"',
        'application/merge-patch+json; charset=utf-8',
      );
      expect(adapter.bodies.single, r'"merge \"me\""');
    });

    test('a non-ASCII string is encoded as UTF-8', () async {
      final adapter = await send('Київ', 'application/json');
      expect(adapter.bodies.single, '"Київ"');
    });
  });

  group('text/json is JSON, as Dio reads it', () {
    test('a string is quoted and a map is encoded', () async {
      final text = await send('{"a":1}', 'text/json');
      expect(text.bodies.single, r'"{\"a\":1}"');
      final map = await send({'a': 1}, 'text/json; charset=utf-8');
      expect(map.bodies.single, '{"a":1}');
    });
  });

  group('Dio keeps what it encodes right', () {});

  group('a body that is not JSON stays as it is', () {
    test('text is sent unquoted', () async {
      final adapter = await send('hello "q"', 'text/plain');
      expect(adapter.bodies.single, 'hello "q"');
      expect(
        FakeTransport.header(adapter.requests.single, 'content-type'),
        'text/plain',
      );
    });

    for (final type in [
      'application/json',
      'text/plain',
      'application/octet-stream',
      'application/x-www-form-urlencoded',
      'multipart/form-data',
    ]) {
      test('an absent body sends no Content-Type as $type', () async {
        final adapter = await send(null, type);
        if (type == 'application/json') {
          // A JSON null is a value: a required nullable body.
          expect(adapter.bodies.single, 'null');
          return;
        }
        expect(adapter.bodies.single, '');
        expect(
          FakeTransport.header(adapter.requests.single, 'content-type'),
          isNull,
        );
        expect(
          adapter.requests.single.headers.keys,
          isNot(contains('content-type')),
        );
      });
    }

    test('no body and no content type sends nothing', () async {
      final adapter = await send(null, null);
      expect(adapter.bodies.single, '');
      expect(
        FakeTransport.header(adapter.requests.single, 'content-type'),
        isNull,
      );
    });
  });
}
