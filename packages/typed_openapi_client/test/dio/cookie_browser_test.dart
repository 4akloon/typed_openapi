/// Whether a `Cookie` header set through Dio reaches the server from a
/// browser (M11, spec decision 8): run with `dart test -p chrome` and
/// `--compiler dart2wasm`. The server is `cookie_server.dart`, started on
/// the loopback by `spawnHybridUri`.
@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  late Dio dio;

  /// The `Cookie` header of each request as the interceptors saw it, before
  /// the browser dropped it.
  final cookiesSet = <Object?>[];
  setUp(cookiesSet.clear);
  setUpAll(() async {
    final channel = spawnHybridUri('cookie_server.dart');
    // The port crosses as JSON: dart2wasm reads the number as a double.
    final port = (await channel.stream.first as num).toInt();
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$port'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            cookiesSet.add(options.headers['Cookie']);
            handler.next(options);
          },
        ),
      );
  });

  const probe = OperationInfo(
    operationId: 'probe',
    method: 'GET',
    pathTemplate: '/probe',
  );

  Result<Object?, Never> decode(RawResponse r) => switch (r.statusCode) {
    200 => r.success(r.json),
    _ => r.undocumented(),
  };

  test('the browser drops a Cookie header and sends the others', () async {
    final result = await DioRequestSender(dio).send(
      const OperationRequest(
        probe,
        headers: [HeaderParameter('X-Probe', 'sent')],
        cookies: [CookieParameter('session', 'abc')],
      ),
      decode,
    );
    // The sender produced the header; only the browser dropped it.
    expect(cookiesSet, ['session=abc']);
    final received = (result as Success<Object?, Never>).data! as Map;
    expect(received['probe'], 'sent');
    // `Cookie` is a forbidden request header: XMLHttpRequest and fetch
    // ignore it, so a cookie parameter never reaches the server.
    expect(received['cookie'], isNull);
  });

  test('a Cookie header set on Dio directly is dropped too', () async {
    final response = await dio.get<Map<String, Object?>>(
      '/probe',
      options: Options(headers: {'Cookie': 'session=abc', 'X-Probe': 'raw'}),
    );
    expect(response.data?['probe'], 'raw');
    expect(response.data?['cookie'], isNull);
  });
}
