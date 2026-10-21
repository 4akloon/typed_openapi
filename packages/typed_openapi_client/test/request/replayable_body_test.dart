import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/src/request/replayable_body.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  FileUpload streamed() => const FileUpload.stream(Stream.empty(), length: 0);

  test('bodies that can be built again are replayable', () {
    final bodies = <Object?>[
      null,
      {'a': 1},
      'text',
      FileUpload.bytes(Uint8List(1)),
      const FormBody({'a': 1}),
    ];
    for (final body in bodies) {
      expect(ReplayableBody.isReplayable(body), isTrue, reason: '$body');
    }
  });

  test('a FileUpload.stream is not replayable', () {
    expect(ReplayableBody.isReplayable(streamed()), isFalse);
  });

  test('a multipart body of bytes parts is replayable', () {
    final body = MultipartBody([
      MultipartPart.file('f', FileUpload.bytes(Uint8List(1))),
    ]);
    expect(ReplayableBody.isReplayable(body), isTrue);
  });

  test('a multipart body with a streamed part is not replayable', () {
    final body = MultipartBody([MultipartPart.file('f', streamed())]);
    expect(ReplayableBody.isReplayable(body), isFalse);
  });
}
