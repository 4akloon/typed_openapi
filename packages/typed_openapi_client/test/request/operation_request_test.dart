import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  const operation = OperationInfo(
    operationId: 'listPetTags',
    method: 'GET',
    pathTemplate: '/pets/{petId}/tags{;filter}/{kind}',
    tags: ['pets'],
  );

  group('OperationInfo', () {
    test('prints its method, path and id', () {
      expect(
        '$operation',
        'GET /pets/{petId}/tags{;filter}/{kind} (listPetTags)',
      );
    });
  });

  group('OperationRequest', () {
    test('substitutes path parameters and appends the query in order', () {
      const request = OperationRequest(
        operation,
        path: [
          PathParameter('kind', 'a/b'),
          PathParameter('petId', 7),
          PathParameter(';filter', ['x', 'y'], style: .matrix, explode: true),
        ],
        query: [
          QueryParameter('limit', 10),
          QueryParameter('cursor', null),
          QueryParameter('sort', ['name', '-age'], explode: false),
        ],
      );
      expect(
        request.resolvePath(),
        '/pets/7/tags;%3Bfilter=x;%3Bfilter=y/a%2Fb?limit=10&sort=name,-age',
      );
    });

    test('no query string when every query value is undefined', () {
      const request = OperationRequest(
        OperationInfo(
          operationId: 'list',
          method: 'GET',
          pathTemplate: '/pets',
        ),
        query: [QueryParameter('tag', null)],
      );
      expect(request.resolvePath(), '/pets');
    });

    test('a placeholder without a value is a programming error', () {
      expect(
        () => const OperationRequest(operation).resolvePath(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('headers keep order, skip undefined values, join cookies', () {
      const request = OperationRequest(
        operation,
        headers: [
          HeaderParameter('X-Trace', 'abc'),
          HeaderParameter('X-None', null),
          HeaderParameter('X-Ids', [1, 2]),
        ],
        cookies: [
          CookieParameter('session', 's 1'),
          CookieParameter('none', null),
          CookieParameter('theme', 'dark'),
        ],
      );
      expect(request.resolveHeaders(), {
        'X-Trace': 'abc',
        'X-Ids': '1,2',
        'Cookie': 'session=s%201; theme=dark',
      });
      expect(request.resolveHeaders().keys, ['X-Trace', 'X-Ids', 'Cookie']);
      expect(const OperationRequest(operation).resolveHeaders(), isEmpty);
      expect(const OperationRequest(operation).streamStatuses, isEmpty);
    });
  });

  group('RawResponse', () {
    JsonDecodeException failure(Object? Function() body) {
      try {
        body();
      } on JsonDecodeException catch (e) {
        return e;
      }
      fail('expected a JsonDecodeException');
    }

    const json = {
      'content-type': ['application/json; charset=utf-8'],
    };
    const text = {
      'content-type': ['text/plain'],
    };

    test('json is the body as Dio parsed it, never re-parsed', () {
      expect(const RawResponse(statusCode: 200, body: {'a': 1}).json, {
        'a': 1,
      });
      expect(
        const RawResponse(
          statusCode: 200,
          body: '{"a": 1}',
          headers: text,
        ).json,
        '{"a": 1}',
      );
      expect(const RawResponse(statusCode: 204).json, isNull);
      expect(
        failure(
          () => const RawResponse(statusCode: 200, body: '{"a": 1}').jsonObject,
        ).message,
        'expected an object, got a string',
      );
      expect(
        failure(
          () => const RawResponse(statusCode: 200, body: [1]).jsonObject,
        ).message,
        'expected an object, got an array',
      );
    });

    test('nesting deeper than maxDepth is a decode error', () {
      final deep = jsonDecode('[' * 1001 + ']' * 1001);
      expect(
        failure(() => RawResponse(statusCode: 200, body: deep).json).path,
        hasLength(1000),
      );
    });

    test('text and bytes', () {
      expect(const RawResponse(statusCode: 200, body: 'hi').text, 'hi');
      expect(const RawResponse(statusCode: 204).text, '');
      final bytes = Uint8List.fromList([1, 2]);
      expect(RawResponse(statusCode: 200, body: bytes).bytes, same(bytes));
      expect(const RawResponse(statusCode: 204).bytes, isEmpty);
      expect(
        failure(
          () => const RawResponse(statusCode: 200, body: {'a': 1}).text,
        ).expected,
        'a text body',
      );
      expect(
        failure(
          () => const RawResponse(statusCode: 200, body: 'x').bytes,
        ).actual,
        'a string',
      );
    });

    test('parse reads bodies the HTTP client did not parse', () {
      expect(RawResponse.parse(utf8.encode('{"a": 1}'), json), {'a': 1});
      expect(RawResponse.parse(utf8.encode('{"a": 1}'), text), '{"a": 1}');
      expect(RawResponse.parse(Uint8List(0), json), isNull);
      expect(
        failure(() => RawResponse.parse(utf8.encode('{'), json)).message,
        'expected a JSON body, got text that is not JSON',
      );
      expect(
        RawResponse.isJson({
          'content-type': ['application/problem+json'],
        }),
        isTrue,
      );
      expect(RawResponse.isJson(const {}), isFalse);
    });

    test('result helpers carry status, headers and body', () {
      const response = RawResponse(
        statusCode: 404,
        body: 'gone',
        headers: text,
      );
      final ok = response.success<int, String>(1) as Success<int, String>;
      expect((ok.data, ok.statusCode, ok.headers), (1, 404, text));
      final error = response.error<int, String>('e') as HttpError<int, String>;
      expect((error.body, error.statusCode), ('e', 404));
      final undocumented =
          response.undocumented<int, String>()
              as UndocumentedStatus<int, String>;
      expect((undocumented.statusCode, undocumented.rawBody), (404, 'gone'));
      expect(undocumented.headers, text);
    });
  });
}
