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

  (ClientSender, FakeTransport) senderFor(FakeTransport adapter) => (
    ClientSender(adapter),
    adapter,
  );

  FakeTransport noContent() =>
      FakeTransport((_) => FakeTransport.response('', 204));

  test('a form body is sent as text with its content type', () async {
    final (sender, adapter) = senderFor(noContent());
    final result = await sender.send(
      const OperationRequest(
        upload,
        body: FormBody({'name': 'a b', 'n': 1}),
        contentType: 'application/x-www-form-urlencoded',
      ),
      decodeVoid,
    );
    expect(result, isA<Success<void, Never>>());
    expect(adapter.bodies.single, 'name=a%20b&n=1');
    expect(
      FakeTransport.header(adapter.requests.single, 'content-type'),
      'application/x-www-form-urlencoded',
    );
  });

  test('a multipart body has text, JSON and file parts', () async {
    final (sender, adapter) = senderFor(noContent());
    await sender.send(
      OperationRequest(
        upload,
        body: MultipartBody([
          const MultipartPart.value('note', 'hi'),
          const MultipartPart.value('count', 2),
          const MultipartPart.value('meta', {'k': 'v'}),
          const MultipartPart.value('ids', [1, 2]),
          const MultipartPart.value('gone', null),
          const MultipartPart.value('raw', 'x', contentType: 'text/csv'),
          const MultipartPart.value(
            'quoted',
            'y',
            contentType: 'application/json',
          ),
          MultipartPart.file(
            'file',
            FileUpload.bytes(
              Uint8List.fromList(utf8.encode('abc')),
              filename: 'a.txt',
              contentType: 'text/plain',
            ),
          ),
          MultipartPart.file(
            'stream',
            FileUpload.stream(Stream.value(utf8.encode('de')), length: 2),
          ),
          MultipartPart.file(
            'typed',
            FileUpload.bytes(Uint8List.fromList(utf8.encode('f'))),
            contentType: 'image/png',
          ),
          MultipartPart.file(
            'own',
            FileUpload.bytes(
              Uint8List.fromList(utf8.encode('g')),
              contentType: 'image/gif',
            ),
            contentType: 'image/png',
          ),
        ]),
        contentType: 'multipart/form-data',
      ),
      decodeVoid,
    );
    final type =
        FakeTransport.header(adapter.requests.single, 'content-type') as String;
    expect(type, startsWith('multipart/form-data; boundary='));
    final body = adapter.bodies.single;
    expect(body, contains('name="note"\r\n\r\nhi\r\n'));
    expect(body, contains('name="count"\r\n\r\n2\r\n'));
    expect(
      body,
      contains(
        'name="meta"\r\ncontent-type: application/json; charset=utf-8\r\n'
        '\r\n{"k":"v"}\r\n',
      ),
    );
    expect('name="ids"'.allMatches(body), hasLength(2));
    expect(body, isNot(contains('gone')));
    expect(body, contains('name="raw"\r\ncontent-type: text/csv'));
    expect(body, contains('charset=utf-8\r\n\r\n"y"\r\n'));
    expect(
      body,
      contains(
        'name="file"; filename="a.txt"\r\ncontent-type: text/plain\r\n\r\n'
        'abc\r\n',
      ),
    );
    expect(
      body,
      contains(
        'name="stream"\r\ncontent-type: application/octet-stream\r\n\r\n'
        'de\r\n',
      ),
    );
    expect(body, contains('name="typed"\r\ncontent-type: image/png\r\n'));
    expect(body, contains('name="own"\r\ncontent-type: image/gif\r\n'));
  });

  test('a file body sends its bytes or stream and its own type', () async {
    final (sender, adapter) = senderFor(noContent());
    await sender.send(
      OperationRequest(
        upload,
        body: FileUpload.bytes(Uint8List.fromList(utf8.encode('png'))),
        contentType: 'application/octet-stream',
      ),
      decodeVoid,
    );
    await sender.send(
      OperationRequest(
        upload,
        body: FileUpload.stream(
          Stream.fromIterable([utf8.encode('a'), utf8.encode('bc')]),
          length: 3,
          contentType: 'image/png',
        ),
        contentType: 'application/octet-stream',
      ),
      decodeVoid,
    );
    expect(adapter.bodies, ['png', 'abc']);
    expect(
      FakeTransport.header(adapter.requests.first, 'content-type'),
      'application/octet-stream',
    );
    expect(
      FakeTransport.header(adapter.requests.last, 'content-type'),
      'image/png',
    );
    expect(FakeTransport.header(adapter.requests.last, 'content-length'), '3');
  });

  test('a binary operation decodes a JSON error body', () async {
    final sender = ClientSender(FakeTransport.json(404, {'code': 'gone'}));
    Result<Uint8List, Object?> decode(RawResponse r) => switch (r.statusCode) {
      200 => r.success(r.bytes),
      404 => r.error(JsonReader.asObject(r.parsedJson)['code']),
      _ => r.undocumented(),
    };
    final result = await sender.send(
      const OperationRequest(
        OperationInfo(
          operationId: 'download',
          method: 'GET',
          pathTemplate: '/files/a',
        ),
        responseKind: .bytes,
      ),
      decode,
    );
    expect(result, isA<HttpError<Uint8List, Object?>>());
    expect((result as HttpError<Uint8List, Object?>).body, 'gone');
  });
}
