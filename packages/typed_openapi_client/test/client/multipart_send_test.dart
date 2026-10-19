import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

void main() {
  const upload = OperationInfo(
    operationId: 'upload',
    method: 'POST',
    pathTemplate: '/files',
  );

  Result<void, Never> decodeVoid(RawResponse r) =>
      r.statusCode == 204 ? r.success(null) : r.undocumented();

  FakeTransport noContent() =>
      FakeTransport((_) => FakeTransport.response('', 204));

  /// Sends [parts] as a multipart body and returns the adapter that saw it.
  Future<FakeTransport> sendParts(List<MultipartPart> parts) async {
    final adapter = noContent();
    await ClientSender(adapter).send(
      OperationRequest(
        upload,
        body: MultipartBody(parts),
        contentType: 'multipart/form-data',
      ),
      decodeVoid,
    );
    return adapter;
  }

  Future<Result<void, Never>> send(OperationRequest request) =>
      ClientSender(noContent()).send(request, decodeVoid);

  FileUpload file([String content = 'x', String? contentType]) =>
      FileUpload.bytes(
        Uint8List.fromList(utf8.encode(content)),
        contentType: contentType,
      );

  /// The part names of a multipart body, in wire order.
  List<String> names(String body) => [
    for (final match in RegExp('name="([^"]*)"').allMatches(body))
      match.group(1)!,
  ];

  group('the order of the parts', () {
    test('is the order of toParts, files and values mixed', () async {
      final adapter = await sendParts([
        MultipartPart.file('file', file()),
        const MultipartPart.value('after', 'a'),
        const MultipartPart.value('meta', {'a': 1}),
        const MultipartPart.value('before', 'b'),
        MultipartPart.file('last', file('y')),
      ]);
      expect(names(adapter.bodies.single), [
        'file',
        'after',
        'meta',
        'before',
        'last',
      ]);
    });

    test('keeps text before files without a content type', () async {
      final adapter = await sendParts([
        const MultipartPart.value('a', 'x'),
        MultipartPart.file('f', file()),
      ]);
      final body = adapter.bodies.single;
      expect(body, contains('name="a"\r\n\r\nx\r\n'));
      expect(names(body), ['a', 'f']);
    });

    test('a list value keeps its items together and in place', () async {
      final adapter = await sendParts([
        const MultipartPart.value('first', 'a'),
        MultipartPart.file('f', file()),
        const MultipartPart.value('ids', [1, 2]),
        const MultipartPart.value('last', 'z'),
      ]);
      expect(names(adapter.bodies.single), [
        'first',
        'f',
        'ids',
        'ids',
        'last',
      ]);
    });
  });

  group('a part name and file name', () {
    test('are escaped, never ending the header line', () async {
      final adapter = await sendParts([
        const MultipartPart.value('a"b\r\nX-Evil: 1', 'v'),
        MultipartPart.file(
          'f',
          FileUpload.bytes(
            Uint8List(1),
            filename: 'é"\r\nContent-Type: evil\r\n\r\nx.txt',
          ),
        ),
      ]);
      final body = adapter.bodies.single;
      expect(body, contains('name="a%22b%0D%0AX-Evil: 1"'));
      expect(body, contains('filename="é%22%0D%0AContent-Type: evil'));
      expect(body, isNot(contains('\r\nX-Evil: 1\r\n')));
    });
  });

  group('a part that cannot be sent', () {
    for (final (name, value) in <(String, Object?)>[
      ('NaN', double.nan),
      ('infinity', double.infinity),
      ('an object', Object()),
      (
        'a nested list',
        [
          [1, 2],
          [3],
        ],
      ),
      ('a list of objects that are not JSON', [Object()]),
      ('a map with a value that is not JSON', {'a': Object()}),
    ]) {
      test('$name throws ArgumentError', () {
        expect(
          () => sendParts([MultipartPart.value('p', value)]),
          throwsArgumentError,
        );
      });
    }

    test('a map with a text media type throws and names it', () {
      expect(
        () => sendParts([
          const MultipartPart.value('m', {'a': 1}, contentType: 'text/csv'),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('text/csv'),
          ),
        ),
      );
    });

    test('a map with a JSON media type is JSON', () async {
      final adapter = await sendParts([
        const MultipartPart.value(
          'm',
          {'a': 1},
          contentType: 'application/vnd.x+json',
        ),
      ]);
      expect(adapter.bodies.single, contains('{"a":1}'));
    });
  });

  group('a content type that is not a media type', () {
    test('of a file part throws FormatException', () {
      expect(
        () => sendParts([
          MultipartPart.file('f', file('x', 'text/plain\r\nX-Evil: 1')),
        ]),
        throwsFormatException,
      );
    });

    test('of a part throws FormatException', () {
      expect(
        () => sendParts([
          const MultipartPart.value('p', 'v', contentType: 'a\r\nb: c'),
        ]),
        throwsFormatException,
      );
    });

    test('of a binary body throws FormatException', () {
      expect(
        () => send(
          OperationRequest(
            upload,
            body: file('x', 'text/plain\r\nX-Evil: 1'),
            contentType: 'application/octet-stream',
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('a stream upload', () {
    test('can be sent once; the second send throws StateError', () async {
      final request = OperationRequest(
        upload,
        body: FileUpload.stream(Stream.value([1, 2]), length: 2),
        contentType: 'application/octet-stream',
      );
      expect(await send(request), isA<Success<void, Never>>());
      expect(() => send(request), throwsStateError);
    });
  });

  group('a form value', () {
    test('that is not ASCII or is reserved is percent-encoded', () async {
      final adapter = noContent();
      await ClientSender(adapter).send(
        const OperationRequest(
          upload,
          body: FormBody({'q': 'Київ & co+1', 'r': 'a=b'}),
          contentType: 'application/x-www-form-urlencoded',
        ),
        decodeVoid,
      );
      expect(
        adapter.bodies.single,
        'q=%D0%9A%D0%B8%D1%97%D0%B2%20%26%20co%2B1&r=a%3Db',
      );
    });
  });
}
