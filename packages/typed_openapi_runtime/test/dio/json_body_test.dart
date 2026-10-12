import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';

void main() {
  const operation = OperationInfo(
    operationId: 'send',
    method: 'POST',
    pathTemplate: '/things',
  );

  Result<void, Never> decodeVoid(RawResponse r) =>
      r.statusCode == 204 ? r.success(null) : r.undocumented();

  /// Sends [body] as [contentType] and returns the adapter that saw it.
  Future<FakeAdapter> send(Object? body, String? contentType) async {
    final adapter = FakeAdapter(
      (_) => ResponseBody.fromString('', 204),
    );
    await DioRequestSender(Dio()..httpClientAdapter = adapter).send(
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
        expect(adapter.requests.single.contentType, 'application/json');
      });
    }

    test('a required nullable body that is null sends null', () async {
      final adapter = await send(null, 'application/json');
      expect(adapter.bodies.single, 'null');
      expect(adapter.requests.single.contentType, 'application/json');
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

  group('a body that is not JSON stays as it is', () {
    test('text is sent unquoted', () async {
      final adapter = await send('hello "q"', 'text/plain');
      expect(adapter.bodies.single, 'hello "q"');
      expect(adapter.requests.single.contentType, 'text/plain');
    });

    test('text/json is text', () async {
      final adapter = await send('{"a":1}', 'text/json');
      expect(adapter.bodies.single, '{"a":1}');
    });

    test('no body and no content type sends nothing', () async {
      final adapter = await send(null, null);
      expect(adapter.bodies.single, '');
      expect(adapter.requests.single.contentType, isNull);
    });
  });
}
