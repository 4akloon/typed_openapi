import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

/// Sends one request through your own [Dio] to a local server and prints the
/// result. Generated clients do the same through `DioTransport`.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'id': 1, 'name': 'Rex'}));
    await request.response.close();
  });

  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
  final result = await ClientSender(DioTransport(dio)).send(
    const OperationRequest(
      OperationInfo(
        operationId: 'getPet',
        method: 'GET',
        pathTemplate: '/pets/{id}',
      ),
      path: [PathParameter('id', 1)],
    ),
    (r) => switch (r.statusCode) {
      200 => r.success(r.jsonObject['name']! as String),
      _ => r.undocumented(),
    },
  );
  stdout.writeln(switch (result) {
    Success(:final data) => 'pet: $data',
    _ => 'failed: $result',
  });

  dio.close();
  await server.close(force: true);
}
