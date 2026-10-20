import 'dart:convert';
import 'dart:io';

import 'package:typed_openapi_client/typed_openapi_client.dart';

/// A transport that answers every request with one canned JSON response.
final class CannedTransport implements ClientTransport {
  /// Creates a transport that answers with [status] and [json].
  const CannedTransport(this.status, this.json);

  /// The status of every response.
  final int status;

  /// The JSON text of every response body.
  final String json;

  @override
  Future<TransportResponse> send(TransportRequest request) async =>
      TransportResponse(
        statusCode: status,
        headers: const {
          'content-type': ['application/json'],
        },
        body: Stream.value(utf8.encode(json)),
      );
}

/// What a generated method does: describe the operation, send it, and decode
/// the response by its status.
Future<Result<String, String>> getPetName(
  ClientTransport transport,
  int id,
) => ClientSender(transport).send(
  OperationRequest(
    const OperationInfo(
      operationId: 'getPet',
      method: 'GET',
      pathTemplate: '/pets/{id}',
    ),
    path: [PathParameter('id', id)],
  ),
  (r) => switch (r.statusCode) {
    200 => r.success(r.jsonObject['name']! as String),
    >= 400 && < 600 => r.error(r.jsonObject['title']! as String),
    _ => r.undocumented(),
  },
);

Future<void> main() async {
  for (final transport in const [
    CannedTransport(200, '{"id": 1, "name": "Rex"}'),
    CannedTransport(404, '{"title": "No such pet"}'),
  ]) {
    final line = switch (await getPetName(transport, 1)) {
      Success(:final data) => 'pet: $data',
      HttpError(:final body, :final statusCode) => 'error $statusCode: $body',
      _ => 'something else went wrong',
    };
    stdout.writeln(line);
  }
}
