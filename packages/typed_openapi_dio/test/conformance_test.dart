import 'package:dio/dio.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';
import 'package:typed_openapi_transport_tests/typed_openapi_transport_tests.dart';

const _noStreaming =
    "Dio's default browser adapter delivers a body only when the "
    'connection closes, so DioTransport refuses event streams there.';

const _eventCases = [
  'events arrive, reconnect with Last-Event-ID and end on cancel',
  'pieces that split a line and a character are joined',
  'retry sets the delay of the reconnection',
  'a 204 ends the stream',
  'an error status with a body is the typed error',
  'a listener cancel closes the connection',
];

void main() {
  final isWeb = DioTransport(Dio()).isWeb;
  TransportConformance(
    (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
    createWithTimeout: (baseUrl, timeout) => DioTransport(
      Dio(
        BaseOptions(
          baseUrl: '$baseUrl',
          connectTimeout: timeout,
          receiveTimeout: timeout,
        ),
      ),
    ),
    skips: {
      if (isWeb) ...{
        for (final name in _eventCases) name: _noStreaming,
        'a cancel during the body is Cancelled':
            "Dio's default browser adapter delivers a body only when the "
            'connection closes, so there is no body to cancel in the middle.',
      },
    },
  ).register();
}
