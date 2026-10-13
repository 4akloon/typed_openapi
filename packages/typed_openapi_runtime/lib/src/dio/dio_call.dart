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
  /// call's. A reconnection of an event stream sends [lastEventId] as
  /// `Last-Event-ID` when it is not empty and a valid header value.
  Future<Response<Object?>> send(
    OperationRequest request,
    CallOptions? call, {
    bool events = false,
    CancelToken? cancelToken,
    String lastEventId = '',
  }) {
    final options = _options(
      request,
      call,
      events: events,
      lastEventId: lastEventId,
    );
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
    required String lastEventId,
  }) => Options(
    method: request.operation.method,
    headers: {
      'Accept': ?(events ? 'text/event-stream' : request.accept),
      ...request.resolveHeaders(),
      for (final MapEntry(:key, :value) in call?.headers.entries ?? const [])
        key: ?value,
      if (_isHeaderValue(lastEventId)) 'Last-Event-ID': lastEventId,
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

  /// Whether [id] is a non-empty header value that every HTTP client sends:
  /// printable ASCII, spaces and tabs. The VM's `HttpClient` throws on any
  /// other character, which would fail every reconnection; a browser sends
  /// UTF-8, so the id is dropped on both and the stream reconnects without
  /// `Last-Event-ID`.
  static bool _isHeaderValue(String id) =>
      id.isNotEmpty &&
      id.codeUnits.every((c) => c == 0x09 || (c >= 0x20 && c <= 0x7E));

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
