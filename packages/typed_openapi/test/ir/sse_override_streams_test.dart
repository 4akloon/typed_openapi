import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose `multi` has two event-stream successes (200, and 201 with a
/// charset), `shared` and `other` that share one stream response, `plain`
/// without a stream and a `feed` of text events.
const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /multi:
    get:
      operationId: multi
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            text/event-stream; charset=utf-8: {schema: {type: string}}
  /shared:
    get:
      operationId: shared
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /other:
    get:
      operationId: other
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /plain:
    get:
      operationId: plain
      responses:
        "204": {description: none}
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
components:
  responses:
    Events:
      description: shared
      content:
        text/event-stream: {schema: {type: string}}
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''';

/// The IR of the spec with the overrides [overrides], its methods by name,
/// and the fixture.
(Map<String, OperationIr>, ClientIr, IrFixture) _build(String overrides) {
  final fixture = IrFixture(_spec, overrides: overrides);
  final ir = fixture.build();
  return (
    {
      for (final group in ir.groups)
        for (final o in group.operations) o.name: o,
    },
    ir,
    fixture,
  );
}

void main() {
  group('events with several event-stream successes', () {
    test('give one stream method with one union', () {
      final (methods, _, fixture) = _build('''
operations:
  multi: {sse: {events: {a: Delta, b: null}}}
''');
      final union = methods['multi']!.events!.union!;
      expect(
        [for (final v in union.variants) v.event],
        ['a', 'b'],
      );
      expect(methods.keys.where((n) => n.startsWith('multi')), ['multi']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });

    test('and data give the same stream', () {
      final (methods, _, fixture) = _build('''
operations:
  multi: {sse: {data: Delta}}
''');
      expect(methods['multi']!.events!.data, isNotNull);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });

    test('replace the itemSchema of each success in OpenAPI 3.2', () {
      final fixture = IrFixture(
        '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /multi:
    get:
      operationId: multi
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: string}}}
        "201":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: integer}}}
components:
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''',
        overrides: '''
operations:
  multi: {sse: {events: {a: Delta}}}
''',
      );
      final methods = [
        for (final group in fixture.build().groups)
          for (final o in group.operations) o.name,
      ];
      expect(methods, ['multi']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });
  });
}
