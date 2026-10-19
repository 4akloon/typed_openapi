import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  group('FormBody', () {
    test('writes each property like a form query parameter', () {
      const body = FormBody({
        'name': 'Rex Jr',
        'tags': ['a', 'b'],
        'gone': null,
        'age': 3,
      });
      expect(body.encode(), 'name=Rex%20Jr&tags=a&tags=b&age=3');
    });

    test('follows the encoding of each property', () {
      const body = FormBody(
        {
          'tags': ['a', 'b'],
          'meta': {'k': 'v', 'n': 1},
          'next': '/a/b?c',
          'filter': {'x': 1},
        },
        {
          'tags': FormEncoding(explode: false),
          'meta': FormEncoding(style: .deepObject),
          'next': FormEncoding(allowReserved: true),
          'filter': FormEncoding(json: true),
        },
      );
      expect(
        body.encode(),
        'tags=a,b&meta%5Bk%5D=v&meta%5Bn%5D=1&next=/a/b?c&'
        'filter=%7B%22x%22%3A1%7D',
      );
    });

    test('an empty or null object is an empty body', () {
      expect(const FormBody(null).encode(), '');
      expect(const FormBody(<String, Object?>{}).encode(), '');
    });

    test('a body that is not an object, or nested too deep, throws', () {
      expect(() => const FormBody([1]).encode(), throwsArgumentError);
      expect(
        () => const FormBody({
          'a': {
            'b': {'c': 1},
          },
        }).encode(),
        throwsArgumentError,
      );
    });
  });

  group('MultipartBody', () {
    test('a JSON object gives a value part per property', () {
      final body = MultipartBody.fromJson({
        'a': 1,
        'b': [true],
      });
      expect([for (final p in body.parts) p.name], ['a', 'b']);
      expect(
        [for (final p in body.parts) p.value],
        [
          1,
          [true],
        ],
      );
      expect(MultipartBody.fromJson(null).parts, isEmpty);
      expect(() => MultipartBody.fromJson([1]), throwsArgumentError);
    });
  });

  group('FileUpload', () {
    test('holds bytes or a stream with its length', () {
      final bytes = FileUpload.bytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'a.png',
        contentType: 'image/png',
      );
      expect(bytes.length, 3);
      expect(bytes.stream, isNull);
      expect('$bytes', 'FileUpload(a.png, 3 bytes, image/png)');
      final stream = FileUpload.stream(Stream.value([1]), length: 1);
      expect(stream.bytes, isNull);
      expect('$stream', 'FileUpload(unnamed, 1 bytes)');
    });
  });

  group('security metadata', () {
    test('an operation lists alternatives of required schemes', () {
      const bearer = SecurityScheme('bearer', .http, scheme: 'bearer');
      const key = SecurityScheme(
        'key',
        .apiKey,
        parameterName: 'X-Key',
        location: .header,
      );
      const info = OperationInfo(
        operationId: 'getPet',
        method: 'GET',
        pathTemplate: '/pets',
        security: [
          [
            SecurityUse(bearer, ['read']),
          ],
          [SecurityUse(key)],
          [],
        ],
      );
      expect(info.security, hasLength(3));
      expect('${info.security.first.single}', 'bearer read');
      expect('${info.security[1].single}', 'key');
      expect('$key', 'SecurityScheme(key, apiKey)');
      expect(
        const OperationInfo(
          operationId: 'x',
          method: 'GET',
          pathTemplate: '/',
        ).security,
        isEmpty,
      );
    });

    test('a scheme the spec does not define is an unknown requirement', () {
      const info = OperationInfo(
        operationId: 'getPet',
        method: 'GET',
        pathTemplate: '/pets',
        security: [
          [
            SecurityUse(SecurityScheme('nope', .unknown), ['read']),
          ],
        ],
      );
      final alternative = info.security.single;
      expect(alternative, isNotEmpty);
      expect(alternative.single.scheme.type, SecuritySchemeType.unknown);
      expect('${alternative.single.scheme}', 'SecurityScheme(nope, unknown)');
    });
  });

  group('RawResponse', () {
    const jsonHeaders = {
      'content-type': ['application/json'],
    };

    test('parses JSON a text or binary operation read as text or bytes', () {
      final bytes = RawResponse(
        statusCode: 404,
        body: Uint8List.fromList(utf8.encode('{"code":"gone"}')),
        headers: jsonHeaders,
      );
      expect(bytes.parsedJson, {'code': 'gone'});
      const text = RawResponse(
        statusCode: 404,
        body: '{"code":"gone"}',
        headers: jsonHeaders,
      );
      expect(text.parsedJson, {'code': 'gone'});
      const plain = RawResponse(statusCode: 404, body: 'gone');
      expect(plain.parsedJson, 'gone');
      const parsed = RawResponse(statusCode: 200, body: {'a': 1});
      expect(parsed.parsedJson, {'a': 1});
    });

    test('rejects JSON nested too deep when it parses it', () {
      final deep = '${'[' * 1001}${']' * 1001}';
      expect(
        () => RawResponse(
          statusCode: 404,
          body: Uint8List.fromList(utf8.encode(deep)),
          headers: jsonHeaders,
        ).parsedJson,
        throwsA(isA<JsonDecodeException>()),
      );
      expect(
        () => RawResponse.parse(
          Uint8List.fromList(utf8.encode(deep)),
          jsonHeaders,
        ),
        throwsA(isA<JsonDecodeException>()),
      );
    });

    test('reads the text of a body the client read as bytes', () {
      final response = RawResponse(
        statusCode: 200,
        body: Uint8List.fromList(utf8.encode('héllo')),
      );
      expect(response.text, 'héllo');
      expect(
        () => RawResponse(
          statusCode: 200,
          body: Uint8List.fromList([0xff]),
        ).text,
        throwsFormatException,
      );
    });
  });

  test('a path variable is any text between braces without a brace', () {
    String variables(String path) => [
      for (final m in OperationRequest.pathVariable.allMatches(path)) m[1],
    ].join('|');
    expect(variables('/a/{id}/{b-c}'), 'id|b-c');
    expect(variables('/c/{}'), '');
    expect(OperationRequest.pathVariable.allMatches('/c/{}'), hasLength(1));
    expect(variables('/x/{a{b}'), 'b');
    const request = OperationRequest(
      OperationInfo(operationId: 'x', method: 'GET', pathTemplate: '/c/{}'),
    );
    expect(request.resolvePath, throwsArgumentError);
  });
}
