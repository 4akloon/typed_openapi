import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/src/request/body_encoder.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

const _upload = OperationInfo(
  operationId: 'upload',
  method: 'POST',
  pathTemplate: '/files',
);

/// The encoded body of [body] sent as [contentType]: its media type and
/// text, or null when nothing is sent.
Future<(String?, String)?> encode(Object? body, String? contentType) async {
  final encoded = BodyEncoder(() => 'b').encode(
    OperationRequest(_upload, body: body, contentType: contentType),
  );
  if (encoded == null) return null;
  final bytes = await encoded.read().expand((chunk) => chunk).toList();
  expect(encoded.length, bytes.length);
  return (encoded.contentType, utf8.decode(bytes));
}

void main() {
  group('a JSON content type makes any value JSON text', () {
    for (final (value, text) in [
      ({'a': 1}, '{"a":1}'),
      ([1, 'x'], '[1,"x"]'),
      ('a"b', r'"a\"b"'),
      (3, '3'),
      (true, 'true'),
      (null, 'null'),
      ('é', '"é"'),
    ]) {
      test('$value', () async {
        expect(await encode(value, 'application/json'), (
          'application/json',
          text,
        ));
      });
    }

    test('text/json and +json types too', () async {
      expect(await encode('s', 'text/json'), ('text/json', '"s"'));
      expect(await encode('s', 'application/problem+json'), (
        'application/problem+json',
        '"s"',
      ));
    });
  });

  test('text is sent as it is, in UTF-8', () async {
    expect(await encode('plain "t" é', 'text/plain'), (
      'text/plain',
      'plain "t" é',
    ));
  });

  test('no body and a content type that is not JSON sends nothing', () async {
    expect(await encode(null, 'text/plain'), isNull);
    expect(await encode(null, null), isNull);
  });

  test('a form body is its text with its content type', () async {
    expect(
      await encode(
        const FormBody({'name': 'a b', 'n': 1}),
        'application/x-www-form-urlencoded',
      ),
      ('application/x-www-form-urlencoded', 'name=a%20b&n=1'),
    );
  });

  test('a multipart body names its boundary', () async {
    expect(
      await encode(
        const MultipartBody([MultipartPart.value('a', 'b')]),
        'multipart/form-data',
      ),
      (
        'multipart/form-data; boundary=b',
        '--b\r\ncontent-disposition: form-data; name="a"\r\n\r\nb\r\n--b--\r\n',
      ),
    );
  });

  test('a file body has its own media type, else the spec\'s', () async {
    final png = Uint8List.fromList(utf8.encode('png'));
    expect(await encode(FileUpload.bytes(png), 'application/octet-stream'), (
      'application/octet-stream',
      'png',
    ));
    expect(
      await encode(
        FileUpload.stream(
          Stream.value(utf8.encode('gif')),
          length: 3,
          contentType: 'image/GIF',
        ),
        'application/octet-stream',
      ),
      ('image/GIF', 'gif'),
    );
    expect(
      () => encode(FileUpload.bytes(png, contentType: 'png'), null),
      throwsFormatException,
    );
  });

  test('bytes held in memory are read in chunks of 1024 bytes', () async {
    final encoded = BodyEncoder(() => 'b').encode(
      OperationRequest(
        _upload,
        body: FileUpload.bytes(Uint8List(2500)),
        contentType: 'application/octet-stream',
      ),
    );
    expect(await encoded!.read().map((c) => c.length).toList(), [
      1024,
      1024,
      452,
    ]);
  });
}
