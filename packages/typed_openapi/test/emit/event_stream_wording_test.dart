import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

/// A spec with a GET `watch` that streams text and a `plain` without a
/// stream.
const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /watch:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
  /plain:
    get:
      operationId: plain
      tags: [t]
      responses:
        "204": {description: none}
''';

/// The code of the API file of [_spec] with [overrides], and the fixture.
(String, IrFixture) _generate(String overrides) {
  final fixture = IrFixture(_spec, overrides: overrides);
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  final files = const ApiLibrary().files(ir, client: 'api');
  return (files['api/t_api.dart']!, fixture);
}

/// [code] with every doc line break joined, so wrapped prose can be found.
String _joined(String code) => code.replaceAll(RegExp(r'\n\s*/// ?'), ' ');

void main() {
  group('the doc of a GET stream that its override turns off', () {
    test('says the override turns reconnection off', () {
      final (code, _) = _generate(
        'operations:\n  watch: {sse: {reconnect: false}}\n',
      );
      expect(
        _joined(code),
        contains(
          "It does not reconnect: the operation's `sse.reconnect` override "
          'turns it off.',
        ),
      );
      expect(_joined(code), isNot(contains('unless the operation')));
    });

    test('is the one of a POST that does not enable it, for a POST', () {
      final (code, _) = _generate('');
      expect(_joined(code), isNot(contains('override turns it off')));
    });
  });

  test('TOA669 says "changes" for one field and "change" for several', () {
    final (_, one) = _generate(
      'operations:\n  plain: {sse: {reconnect: true}}\n',
    );
    final message = one
        .reportedOf(DiagnosticCode.sseOverrideNotApplied)
        .single
        .message;
    expect(message, endsWith('so "reconnect" of "sse" changes nothing.'));
    final (_, several) = _generate(
      'operations:\n  plain: {sse: {reconnect: true, method: only}}\n',
    );
    expect(
      several.reportedOf(DiagnosticCode.sseOverrideNotApplied).single.message,
      endsWith('so "reconnect", "method" of "sse" change nothing.'),
    );
  });
}
