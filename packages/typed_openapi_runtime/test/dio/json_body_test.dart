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

  group('text/json is JSON, as Dio reads it', () {
    test('a string is quoted and a map is encoded', () async {
      final text = await send('{"a":1}', 'text/json');
      expect(text.bodies.single, r'"{\"a\":1}"');
      final map = await send({'a': 1}, 'text/json; charset=utf-8');
      expect(map.bodies.single, '{"a":1}');
    });
  });

  group('Dio keeps what it encodes right', () {
    test('an interceptor sees the map or list of a JSON body', () async {
      final seen = <Object?>[];
      final adapter = FakeAdapter((_) => ResponseBody.fromString('', 204));
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              seen.add(options.data);
              handler.next(options);
            },
          ),
        );
      final sender = DioRequestSender(dio);
      for (final body in <Object?>[
        {'name': 'Rex', 'tags': <Object?>[]},
        [1, 2],
        7,
        true,
      ]) {
        await sender.send(
          OperationRequest(
            operation,
            body: body,
            contentType: 'application/merge-patch+json',
          ),
          decodeVoid,
        );
      }
      expect(seen, [
        {'name': 'Rex', 'tags': <Object?>[]},
        [1, 2],
        7,
        true,
      ]);
      expect(adapter.bodies, [
        '{"name":"Rex","tags":[]}',
        '[1,2]',
        '7',
        'true',
      ]);
    });

    test('an interceptor sees the string and null that are encoded', () async {
      final seen = <Object?>[];
      final dio = Dio()
        ..httpClientAdapter = FakeAdapter(
          (_) => ResponseBody.fromString('', 204),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              seen.add(options.data);
              handler.next(options);
            },
          ),
        );
      final sender = DioRequestSender(dio);
      for (final body in <Object?>['a"b', null]) {
        await sender.send(
          OperationRequest(
            operation,
            body: body,
            contentType: 'application/json',
          ),
          decodeVoid,
        );
      }
      expect(seen, [r'"a\"b"', 'null']);
    });
  });

  group('a body that is not JSON stays as it is', () {
    test('text is sent unquoted', () async {
      final adapter = await send('hello "q"', 'text/plain');
      expect(adapter.bodies.single, 'hello "q"');
      expect(adapter.requests.single.contentType, 'text/plain');
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
        expect(adapter.requests.single.contentType, isNull);
        expect(
          adapter.requests.single.headers.keys,
          isNot(contains('content-type')),
        );
      });
    }

    test('no body and no content type sends nothing', () async {
      final adapter = await send(null, null);
      expect(adapter.bodies.single, '');
      expect(adapter.requests.single.contentType, isNull);
    });
  });
}
