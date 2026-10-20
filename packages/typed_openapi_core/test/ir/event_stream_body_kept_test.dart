import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_json.dart';

import '../helpers/ir_fixture.dart';

/// The event-stream line of the 200 response of `chat`.
const _stream =
    r"text/event-stream: {schema: {$ref: '#/components/schemas/Delta'}}";

/// A spec whose `chat` offers JSON and [stream] at 200 and only a JSON body
/// at 202, or also [jobStream] there.
String _spec({String stream = _stream, String jobStream = ''}) =>
    '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /chat:
    post:
      operationId: chat
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {\$ref: '#/components/schemas/Reply'}}
            $stream
        "202":
          description: accepted, answered later
          content:
            application/json: {schema: {\$ref: '#/components/schemas/Job'}}
            $jobStream
components:
  schemas:
    Reply: {type: object, properties: {text: {type: string}}}
    Delta: {type: object, properties: {part: {type: string}}}
    Job: {type: object, properties: {id: {type: string}}}
''';

/// The IR of [fixture] as JSON text.
String _json(IrFixture fixture) =>
    IrJson((_) => 'api.yaml').encode(fixture.build());

/// The methods of [fixture] by name.
Map<String, OperationIr> _methods(IrFixture fixture) => {
  for (final group in fixture.build().groups)
    for (final o in group.operations) o.name: o,
};

void main() {
  group('an event stream next to a 2xx with a body that is not one', () {
    test('leaves the method of the body as it is without the stream', () {
      final with_ = IrFixture(_spec());
      final without = IrFixture(_spec(stream: ''));
      expect(_methods(with_).keys, ['chat']);
      expect(_methods(with_)['chat']!.events, isNull);
      expect(_methods(with_)['chat']!.accept, isNull);
      expect(_json(with_), _json(without));
    });

    test('reports the stream method only, naming the statuses (TOA654)', () {
      final fixture = IrFixture(_spec());
      _methods(fixture);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report, hasLength(1));
      expect(report.single.pointer?.value, '#/paths/~1chat/post/responses');
      expect(report.single.message, contains('event-stream method'));
      expect(report.single.message, contains('200'));
      expect(report.single.message, contains('202'));
      expect(report.single.message, isNot(contains('operation is not')));
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamMethodAdded),
        isEmpty,
      );
      expect(fixture.reportedOf(DiagnosticCode.clientEmpty), isEmpty);
    });

    test('is generated with sse.method: only too', () {
      final fixture = IrFixture(
        _spec(),
        overrides: 'operations:\n  chat: {sse: {method: only}}\n',
      );
      expect(_methods(fixture).keys, ['chat']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        hasLength(1),
      );
    });

    test('reports nothing with sse.method: none', () {
      final fixture = IrFixture(
        _spec(),
        overrides: 'operations:\n  chat: {sse: {method: none}}\n',
      );
      expect(_methods(fixture).keys, ['chat']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });
  });

  test('every event-stream success that offers a body keeps both methods', () {
    final fixture = IrFixture(_spec(jobStream: _stream));
    final methods = _methods(fixture);
    expect(methods.keys, ['chat', 'chatStream']);
    expect(methods['chat']!.accept, 'application/json');
    expect(fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated), isEmpty);
  });
}
