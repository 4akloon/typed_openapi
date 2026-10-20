import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';

void main() {
  const plain = OperationRequest(
    OperationInfo(operationId: 'p', method: 'GET', pathTemplate: '/p'),
    headers: [HeaderParameter('X-Tenant', 'from-operation')],
  );
  const stream = OperationRequest(
    OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200},
  );

  Result<String, Never> decode(RawResponse r) => r.undocumented();

  /// The headers of the one request [transport] saw.
  Future<TransportRequest> sentBy(
    FakeTransport transport,
    Future<Object?> Function(ClientSender sender) act,
    CallOptions defaults,
  ) async {
    await act(ClientSender(transport, defaults: defaults));
    return transport.requests.single;
  }

  Future<Object?> events(ClientSender sender, [CallOptions? call]) async {
    final result = await sender.openEvents<String, Never>(
      stream,
      (m) => m.data,
      (r) => r.undocumented(),
      call: call,
    );
    if (result case Success(:final data)) await data.drain<void>();
    return result;
  }

  test('a default Accept does not replace text/event-stream', () async {
    final request = await sentBy(
      FakeTransport.text(200, '', 'text/event-stream'),
      events,
      const CallOptions(headers: {'Accept': 'application/json'}),
    );
    expect(FakeTransport.header(request, 'Accept'), 'text/event-stream');
  });

  test('a default header does not replace one the operation sets', () async {
    final request = await sentBy(
      FakeTransport.json(200, 'x'),
      (sender) => sender.send(plain, decode),
      const CallOptions(headers: {'x-tenant': 'from-default'}),
    );
    expect(FakeTransport.header(request, 'X-Tenant'), 'from-operation');
  });

  test('the call header beats the operation and the default', () async {
    final request = await sentBy(
      FakeTransport.json(200, 'x'),
      (sender) => sender.send(
        plain,
        decode,
        call: const CallOptions(headers: {'X-TENANT': 'from-call'}),
      ),
      const CallOptions(headers: {'X-Tenant': 'from-default'}),
    );
    expect(FakeTransport.header(request, 'X-Tenant'), 'from-call');
  });

  test('a default header the operation does not set is sent', () async {
    final request = await sentBy(
      FakeTransport.json(200, 'x'),
      (sender) => sender.send(plain, decode),
      const CallOptions(headers: {'X-Env': 'prod'}),
    );
    expect(FakeTransport.header(request, 'X-Env'), 'prod');
  });

  test('a default header is sent on an event stream too', () async {
    final request = await sentBy(
      FakeTransport.text(200, '', 'text/event-stream'),
      events,
      const CallOptions(headers: {'X-Env': 'prod'}),
    );
    expect(FakeTransport.header(request, 'X-Env'), 'prod');
  });
}
