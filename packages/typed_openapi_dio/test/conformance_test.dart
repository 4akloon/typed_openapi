import 'package:dio/dio.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';
import 'package:typed_openapi_transport_tests/typed_openapi_transport_tests.dart';

void main() {
  final isWeb = DioTransport(Dio()).isWeb;
  TransportConformance(
    (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
    skips: {
      if (isWeb)
        'events arrive, reconnect with Last-Event-ID and end on cancel':
            "Dio's default browser adapter delivers a body only when the "
            'connection closes, so DioTransport refuses event streams there.',
    },
  ).register();
}
