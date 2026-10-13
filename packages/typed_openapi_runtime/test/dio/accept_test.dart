import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';

void main() {
  const chat = OperationInfo(
    operationId: 'chat',
    method: 'POST',
    pathTemplate: '/chat',
  );

  Future<RequestOptions> sent(
    OperationRequest request, {
    CallOptions? call,
  }) async {
    final adapter = FakeAdapter.json(200, {'ok': true});
    await DioRequestSender(
      Dio()..httpClientAdapter = adapter,
    ).send(request, (r) => r.success(r.json), call: call);
    return adapter.requests.single;
  }

  test('a request with an accept sends it as Accept', () async {
    final options = await sent(
      const OperationRequest(chat, accept: 'application/json'),
    );
    expect(options.headers['Accept'], 'application/json');
  });

  test('a request without an accept sends no Accept', () async {
    final options = await sent(const OperationRequest(chat));
    expect(options.headers.keys.map((k) => k.toLowerCase()), isNot(['accept']));
    expect(options.headers['Accept'], isNull);
  });

  test('an Accept of the call wins, and its map is not changed', () async {
    final headers = {'accept': 'application/vnd.custom+json'};
    final options = await sent(
      const OperationRequest(chat, accept: 'application/json'),
      call: CallOptions(headers: headers),
    );
    expect(options.headers['Accept'], 'application/vnd.custom+json');
    expect(headers, {'accept': 'application/vnd.custom+json'});
  });
}
