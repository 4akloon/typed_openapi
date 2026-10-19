import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of `multipart/form-data` bodies: the exact bytes the server
/// received, written with the fixed boundary `testboundary`.
final class MultipartCases {
  /// Creates the cases on [context].
  const MultipartCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a multipart body arrives whole', _whole)
      ..testCase('a typed multipart part keeps its media type', _typed);
  }

  Future<Map<String, Object?>> _post(List<MultipartPart> parts) async {
    final result = await context.sender.send(
      ConformanceContext.request(
        '/echo',
        method: 'POST',
        body: MultipartBody(parts),
        contentType: 'multipart/form-data',
      ),
      ConformanceContext.echo,
    );
    return (result as Success<Map<String, Object?>, Never>).data;
  }

  void _expectWire(Map<String, Object?> echo, String body) {
    final headers = echo['headers']! as Map<String, Object?>;
    expect(
      headers['content-type'],
      'multipart/form-data; boundary=testboundary',
    );
    expect(echo['body'], body);
    expect(echo['length'], utf8.encode(body).length);
    expect(headers['content-length'], '${utf8.encode(body).length}');
  }

  Future<void> _whole() async {
    final echo = await _post([
      const MultipartPart.value('name', 'Rex'),
      MultipartPart.file(
        'photo',
        FileUpload.bytes(
          Uint8List.fromList([0x61, 0x62, 0x63]),
          filename: 'p.bin',
          contentType: 'application/octet-stream',
        ),
      ),
    ]);
    _expectWire(
      echo,
      '--testboundary\r\n'
      'content-disposition: form-data; name="name"\r\n\r\n'
      'Rex\r\n'
      '--testboundary\r\n'
      'content-disposition: form-data; name="photo"; filename="p.bin"\r\n'
      'content-type: application/octet-stream\r\n\r\n'
      'abc\r\n'
      '--testboundary--\r\n',
    );
  }

  Future<void> _typed() async {
    final echo = await _post([
      const MultipartPart.value(
        'meta',
        {'a': 1},
        contentType: 'application/json',
      ),
      const MultipartPart.value('note', 'hi'),
      MultipartPart.file(
        'data',
        FileUpload.stream(
          Stream.fromIterable([utf8.encode('xy'), utf8.encode('z')]),
          length: 3,
          contentType: 'text/plain',
        ),
      ),
    ]);
    _expectWire(
      echo,
      '--testboundary\r\n'
      'content-disposition: form-data; name="meta"\r\n'
      'content-type: application/json; charset=utf-8\r\n\r\n'
      '{"a":1}\r\n'
      '--testboundary\r\n'
      'content-disposition: form-data; name="note"\r\n'
      'content-type: text/plain; charset=utf-8\r\n\r\n'
      'hi\r\n'
      '--testboundary\r\n'
      'content-disposition: form-data; name="data"\r\n'
      'content-type: text/plain\r\n\r\n'
      'xyz\r\n'
      '--testboundary--\r\n',
    );
  }
}
