import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/src/request/multipart_encoder.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

/// The text [body] encodes to with the boundary `b`, and its length.
Future<(String, int)> encoded(List<MultipartPart> parts) async {
  final body = const MultipartEncoder('b').encode(MultipartBody(parts));
  final bytes = await body.read().expand((chunk) => chunk).toList();
  expect(body.length, bytes.length, reason: 'the length is the byte count');
  return (utf8.decode(bytes, allowMalformed: true), body.length);
}

void main() {
  test('the content type names the boundary', () {
    expect(
      const MultipartEncoder('x-1').contentType,
      'multipart/form-data; boundary=x-1',
    );
  });

  test('values, JSON, lists and files are written as Dio wrote them', () async {
    final (text, _) = await encoded([
      const MultipartPart.value('note', 'hi'),
      const MultipartPart.value('count', 2),
      const MultipartPart.value('ids', [1, 2]),
      const MultipartPart.value('gone', null),
      const MultipartPart.value('meta', {'k': 'v'}),
      const MultipartPart.value('raw', 'x', contentType: 'text/csv'),
      const MultipartPart.value('quoted', 'y', contentType: 'application/json'),
      const MultipartPart.value('late', 'z'),
      MultipartPart.file(
        'file',
        FileUpload.bytes(
          Uint8List.fromList(utf8.encode('abc')),
          filename: 'a.txt',
          contentType: 'TEXT/Plain',
        ),
      ),
      MultipartPart.file(
        'stream',
        FileUpload.stream(Stream.value(utf8.encode('de')), length: 2),
      ),
      MultipartPart.file(
        'own',
        FileUpload.bytes(
          Uint8List.fromList(utf8.encode('g')),
          contentType: 'image/gif',
        ),
        contentType: 'image/png',
      ),
    ]);
    expect(
      text,
      '--b\r\ncontent-disposition: form-data; name="note"\r\n\r\nhi\r\n'
      '--b\r\ncontent-disposition: form-data; name="count"\r\n\r\n2\r\n'
      '--b\r\ncontent-disposition: form-data; name="ids"\r\n\r\n1\r\n'
      '--b\r\ncontent-disposition: form-data; name="ids"\r\n\r\n2\r\n'
      '--b\r\ncontent-disposition: form-data; name="meta"\r\n'
      'content-type: application/json; charset=utf-8\r\n\r\n{"k":"v"}\r\n'
      '--b\r\ncontent-disposition: form-data; name="raw"\r\n'
      'content-type: text/csv; charset=utf-8\r\n\r\nx\r\n'
      '--b\r\ncontent-disposition: form-data; name="quoted"\r\n'
      'content-type: application/json; charset=utf-8\r\n\r\n"y"\r\n'
      '--b\r\ncontent-disposition: form-data; name="late"\r\n'
      'content-type: text/plain; charset=utf-8\r\n\r\nz\r\n'
      '--b\r\ncontent-disposition: form-data; name="file"; '
      'filename="a.txt"\r\ncontent-type: text/plain\r\n\r\nabc\r\n'
      '--b\r\ncontent-disposition: form-data; name="stream"\r\n'
      'content-type: application/octet-stream\r\n\r\nde\r\n'
      '--b\r\ncontent-disposition: form-data; name="own"\r\n'
      'content-type: image/gif\r\n\r\ng\r\n'
      '--b--\r\n',
    );
  });

  test(
    'a charset of the part is kept and used, by its canonical name',
    () async {
      final (text, length) = await encoded([
        const MultipartPart.value(
          'latin',
          'é',
          contentType: 'text/plain; Charset=ISO-8859-1; a="b c"',
        ),
      ]);
      expect(
        text,
        isNot(contains('é')),
        reason: 'é is one byte in ISO-8859-1, not UTF-8',
      );
      expect(
        text,
        contains('content-type: text/plain; charset=iso-8859-1; a="b c"\r\n'),
      );
      expect(length, 118);
    },
  );

  test('names and file names never end the header line', () async {
    final (text, _) = await encoded([
      MultipartPart.file(
        'a"b\r\nc',
        FileUpload.bytes(Uint8List(0), filename: 'x\ny".txt'),
      ),
    ]);
    expect(
      text,
      contains(
        'name="a%22b%0D%0Ac"; filename="x%0D%0Ay%22.txt"\r\n'
        'content-type: application/octet-stream\r\n',
      ),
    );
  });

  group('a part that cannot be sent throws ArgumentError', () {
    for (final (name, value) in [
      ('NaN', double.nan),
      (
        'a nested list',
        [
          [1],
        ],
      ),
      ('an object that is not JSON', {'k': Object()}),
      ('a value that is not JSON', Object()),
    ]) {
      test(name, () {
        expect(
          () => encoded([MultipartPart.value('v', value)]),
          throwsArgumentError,
        );
      });
    }

    test('a map with a text media type', () {
      expect(
        () => encoded([
          const MultipartPart.value('m', {'k': 1}, contentType: 'text/plain'),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('"text/plain"'),
          ),
        ),
      );
    });
  });

  test('a media type that is not one throws FormatException', () {
    expect(
      () => encoded([
        MultipartPart.file(
          'f',
          FileUpload.bytes(Uint8List(0), contentType: 'not a type'),
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => encoded([
        const MultipartPart.value('v', 'x', contentType: 'text/'),
      ]),
      throwsFormatException,
    );
  });
}
