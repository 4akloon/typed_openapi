import 'dart:async';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'dio_failures.dart';
import 'dio_responses.dart';
import 'query_guard.dart';

/// A [ClientTransport] that sends through the user's [Dio], which it uses
/// as it is: its base URL, interceptors, timeouts and adapter apply, and
/// it is never changed.
///
/// Dio reads every response as a stream; the client reads and decodes the
/// bytes, so a `Transformer` or `responseDecoder` of the Dio is not used.
/// An error status goes through Dio's `onError` interceptors first (a
/// token refresh still works) and then reaches the client as a response.
final class DioTransport implements ClientTransport {
  /// Creates the transport over [dio]. [isWeb] tells whether the program
  /// runs in a browser (dart2js or dart2wasm); it is found out when not
  /// given.
  DioTransport(this.dio, {bool? isWeb}) : isWeb = isWeb ?? _runsOnWeb;

  /// The user's Dio instance.
  final Dio dio;

  /// Whether the program runs in a browser, where Dio's default adapter
  /// cannot stream an event stream.
  final bool isWeb;

  static const bool _runsOnWeb = bool.fromEnvironment(
    'dart.library.js_interop',
  );

  /// Explains why server-sent events cannot stream on the web with the
  /// default Dio adapter.
  static const String webStreamingMessage =
      'Server-sent events need a streaming HTTP adapter on the web: Dio\'s '
      'default browser adapter delivers the body only when the connection '
      'closes. Set a fetch-based adapter on your Dio, such as '
      'ConversionLayerAdapter from package:dio_compatibility_layer with '
      'package:http\'s BrowserClient or package:fetch_client.';

  /// The [OperationInfo] of the request [options] describe, for an
  /// interceptor: its tags and security; null for a request this transport
  /// did not send.
  static OperationInfo? operationOf(RequestOptions options) =>
      switch (options.extra[OperationInfo.extraKey]) {
        final OperationInfo info => info,
        _ => null,
      };

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (request.isEventStream && isWeb && _hasDefaultAdapter) {
      throw TransportException(
        .other,
        webStreamingMessage,
        cause: UnsupportedError(webStreamingMessage),
      );
    }
    try {
      return DioResponses.of(
        await dio.request<Object?>(
          QueryGuard(dio.options.baseUrl).target(request.target),
          data: request.body,
          options: _options(request),
          cancelToken: _token(request.cancel),
        ),
      );
    } on DioException catch (e, stackTrace) {
      if (e.response case final Response<Object?> response?
          when response.data is ResponseBody) {
        return DioResponses.of(response);
      }
      throw DioFailures.exception(e, stackTrace);
    }
  }

  Options _options(TransportRequest request) => Options(
    method: request.method,
    headers: {
      for (final MapEntry(:key, :value) in request.headers.entries)
        key: value.length == 1 ? value.single : value.join(', '),
    },
    extra: {...request.extra, OperationInfo.extraKey: request.operation},
    responseType: .stream,
  );

  /// A Dio token that is cancelled with [signal].
  static CancelToken? _token(CancelSignal? signal) {
    if (signal == null) return null;
    final token = CancelToken();
    if (signal.isCancelled) {
      token.cancel(signal.reason);
    } else {
      unawaited(signal.whenCancelled.then((_) => token.cancel(signal.reason)));
    }
    return token;
  }

  bool get _hasDefaultAdapter =>
      dio.httpClientAdapter.runtimeType == HttpClientAdapter().runtimeType;
}
