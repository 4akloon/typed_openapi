import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  const operation = OperationInfo(
    operationId: 'upload',
    method: 'PUT',
    pathTemplate: '/files',
  );

  test('contentLength reads Content-Length in any case', () {
    const request = TransportRequest(
      method: 'PUT',
      target: '/files',
      operation: operation,
      headers: {
        'Content-Length': ['12'],
      },
    );
    expect(request.contentLength, 12);
  });

  test('contentLength is null without Content-Length', () {
    const request = TransportRequest(
      method: 'PUT',
      target: '/files?a=1',
      operation: operation,
    );
    expect(request.contentLength, isNull);
    expect('$request', 'PUT /files?a=1');
  });
}
