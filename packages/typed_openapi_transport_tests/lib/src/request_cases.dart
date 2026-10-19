import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of the request on the wire: method, target, headers, bodies
/// and send progress, as the server's `/echo` saw them.
final class RequestCases {
  /// Creates the cases on [context].
  const RequestCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('the method, target and headers arrive', _target)
      ..testCase(
        'a header given twice reaches the server with both values',
        _repeated,
      )
      ..testCase('PUT, PATCH and DELETE keep their method', _methods)
      ..testCase('a JSON body arrives with its type and length', _json)
      ..testCase('a form body arrives', _form)
      ..testCase('a file stream arrives with its length', _stream)
      ..testCase('send progress reaches the length', _sendProgress);
  }

  Future<Map<String, Object?>> _echo(
    OperationRequest request, {
    CallOptions? call,
  }) async {
    final result = await context.sender.send(
      request,
      ConformanceContext.echo,
      call: call,
    );
    return (result as Success<Map<String, Object?>, Never>).data;
  }

  Future<void> _target() async {
    final echo = await _echo(
      ConformanceContext.request(
        '/echo',
        query: [const QueryParameter('q', 'a b/c')],
        headers: [const HeaderParameter('X-Trace', 't1')],
      ),
      call: const CallOptions(headers: {'X-Call': 'c1'}),
    );
    expect(echo['method'], 'GET');
    expect(echo['target'], '/echo?q=a%20b%2Fc');
    final headers = echo['headers']! as Map<String, Object?>;
    expect((headers['x-trace'], headers['x-call']), ('t1', 'c1'));
  }

  /// `DioTransport` joins the values of a header into one line with `, `,
  /// which is how HTTP reads a repeated header, so the server sees both
  /// values in order.
  Future<void> _repeated() async {
    final echo = await _echo(
      ConformanceContext.request('/echo'),
      call: const CallOptions(
        headers: {
          'X-Multi': ['first', 'second'],
        },
      ),
    );
    final headers = echo['headers']! as Map<String, Object?>;
    expect((headers['x-multi']! as String).split(RegExp(r',\s*')), [
      'first',
      'second',
    ]);
  }

  Future<void> _methods() async {
    for (final method in ['PUT', 'PATCH', 'DELETE']) {
      final echo = await _echo(
        ConformanceContext.request('/echo', method: method),
      );
      expect(echo['method'], method);
    }
  }

  Future<void> _json() async {
    final echo = await _echo(
      ConformanceContext.request(
        '/echo',
        method: 'POST',
        body: {
          'name': 'Rex',
          'tags': ['a'],
        },
        contentType: 'application/json',
      ),
    );
    expect(echo['body'], '{"name":"Rex","tags":["a"]}');
    expect(echo['length'], 27);
    final headers = echo['headers']! as Map<String, Object?>;
    expect(headers['content-type'], startsWith('application/json'));
  }

  Future<void> _form() async {
    final echo = await _echo(
      ConformanceContext.request(
        '/echo',
        method: 'POST',
        body: const FormBody({'a': 'x y', 'b': 1}),
        contentType: 'application/x-www-form-urlencoded',
      ),
    );
    expect(echo['body'], 'a=x%20y&b=1');
  }

  Future<void> _stream() async {
    final echo = await _echo(
      ConformanceContext.request(
        '/echo',
        method: 'POST',
        body: FileUpload.stream(
          Stream.fromIterable([utf8.encode('ab'), utf8.encode('cd')]),
          length: 4,
        ),
        contentType: 'application/octet-stream',
      ),
    );
    expect((echo['body'], echo['length']), ('abcd', 4));
  }

  Future<void> _sendProgress() async {
    final counts = <(int, int)>[];
    await _echo(
      ConformanceContext.request(
        '/echo',
        method: 'POST',
        body: Uint8List(3000),
        contentType: 'application/octet-stream',
      ),
      call: CallOptions(
        onSendProgress: (sent, total) {
          counts.add((sent, total));
        },
      ),
    );
    expect(counts.last, (3000, 3000));
  }
}
