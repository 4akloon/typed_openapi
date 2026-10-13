import 'package:dio/dio.dart';

import '../request/operation_info.dart';
import '../request/operation_request.dart';
import 'call_options.dart';
import 'dio_body.dart';

/// Sends the request of an [OperationRequest] through the user's [Dio]:
/// the method, the finished path and query, the headers, the body and how
/// Dio reads the response. The Dio instance is never changed.
final class DioCall {
  /// Creates the call through [dio].
  const DioCall(this.dio);

  /// The user's Dio instance.
  final Dio dio;

  /// Sends [request] with [call]: for an event stream ([events]) as a
  /// stream with `Accept: text/event-stream`, else read as
  /// [OperationRequest.responseKind] says. [cancelToken] wins over the
  /// call's.
  Future<Response<Object?>> send(
    OperationRequest request,
    CallOptions? call, {
    bool events = false,
    CancelToken? cancelToken,
  }) {
    final options = _options(request, call, events: events);
    // The type argument picks how Dio reads the body: Dio forces JSON for
    // any type but String, List<int> with bytes or ResponseBody with stream.
    Future<Response<R>> send<R>() => dio.request<R>(
      _guardQuery(request.resolvePath()),
      data: const DioBody().data(request),
      options: options,
      cancelToken: cancelToken ?? call?.cancelToken,
      onSendProgress: call?.onSendProgress,
      onReceiveProgress: call?.onReceiveProgress,
    );
    if (events) return send<ResponseBody>();
    return switch (request.responseKind) {
      .json => send<Object?>(),
      .text => send<String>(),
      .bytes => send<List<int>>(),
    };
  }

  Options _options(
    OperationRequest request,
    CallOptions? call, {
    required bool events,
  }) => Options(
    method: request.operation.method,
    headers: {
      if (events) 'Accept': 'text/event-stream',
      ...request.resolveHeaders(),
      for (final MapEntry(:key, :value) in call?.headers.entries ?? const [])
        key: ?value,
      ...const DioBody().headers(request.body),
    },
    extra: {...?call?.extra, OperationInfo.extraKey: request.operation},
    contentType: const DioBody().contentType(request),
    responseType: events
        ? .stream
        : switch (request.responseKind) {
            .json => .json,
            .text => .plain,
            .bytes => .bytes,
          },
  );

  /// Dio joins the base URL and a relative path and then collapses every
  /// `//` of the whole string, query included (`RequestOptions.uri`), which
  /// would change an `allowReserved` value such as `next=/a//b`. When the
  /// query holds `//`, the base URL is joined here, collapsing `//` in the
  /// path part only, and Dio leaves the absolute URL alone. Otherwise the
  /// relative path goes to Dio, so interceptors that change `baseUrl` keep
  /// working; interceptors see the finished URI either way.
  String _guardQuery(String path) {
    final queryStart = path.indexOf('?');
    final base = dio.options.baseUrl;
    if (queryStart < 0 ||
        !path.substring(queryStart).contains('//') ||
        !_absolute.hasMatch(base)) {
      return path;
    }
    final joined = (base + path.substring(0, queryStart)).split(':/');
    final target = joined.length == 2
        ? '${joined[0]}:/${joined[1].replaceAll('//', '/')}'
        : joined.join(':/');
    return target + path.substring(queryStart);
  }

  static final RegExp _absolute = RegExp('^https?:');
}
