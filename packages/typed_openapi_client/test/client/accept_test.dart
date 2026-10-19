import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

void main() {
  const chat = OperationInfo(
    operationId: 'chat',
    method: 'POST',
    pathTemplate: '/chat',
  );

  Future<TransportRequest> sent(
    OperationRequest request, {
    CallOptions? call,
  }) async {
    final adapter = FakeTransport.json(200, {'ok': true});
    await ClientSender(
      adapter,
    ).send(request, (r) => r.success(r.json), call: call);
    return adapter.requests.single;
  }

  test('a request with an accept sends it as Accept', () async {
    final options = await sent(
      const OperationRequest(chat, accept: 'application/json'),
    );
    expect(FakeTransport.header(options, 'Accept'), 'application/json');
  });

  test('a request without an accept sends no Accept', () async {
    final options = await sent(const OperationRequest(chat));
    expect(options.headers.keys.map((k) => k.toLowerCase()), isNot(['accept']));
    expect(FakeTransport.header(options, 'Accept'), isNull);
  });

  test('an Accept of the call wins, and its map is not changed', () async {
    final headers = {'accept': 'application/vnd.custom+json'};
    final options = await sent(
      const OperationRequest(chat, accept: 'application/json'),
      call: CallOptions(headers: headers),
    );
    expect(
      FakeTransport.header(options, 'Accept'),
      'application/vnd.custom+json',
    );
    expect(headers, {'accept': 'application/vnd.custom+json'});
  });
}
