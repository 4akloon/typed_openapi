import 'package:test/test.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec with [paths] (YAML under `paths:`) and [schemas] (under
/// `components.schemas`), in OpenAPI 3.2.
String _spec(String paths, {String schemas = '{}'}) =>
    '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
$paths
components:
  schemas: $schemas
''';

/// The names of the methods of the only group of [ir].
List<String> _names(ClientIr ir) => [
  for (final o in ir.groups.single.operations) o.name,
];

/// The names of the declarations of [ir].
List<String> _declared(ClientIr ir) => [
  for (final d in ir.declarations) d.name,
];

void main() {
  group('event streams that describe their events the same way', () {
    test('with equal inline schemas are one stream, one declaration', () {
      final fixture = IrFixture(
        _spec('''
  /same:
    get:
      operationId: same
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: object, properties: {b: {type: integer}}}}}}
        "201": {description: made, content: {text/event-stream: {schema: {type: object, properties: {b: {type: integer}}}}}}
'''),
      );
      final ir = fixture.build();
      expect(_names(ir), ['same']);
      expect(_declared(ir), ['SameEvent']);
      expect(fixture.reportedOf(.eventStreamNotGenerated), isEmpty);
      expect(fixture.reportedOf(.nameCollision), isEmpty);
    });

    test('with one referenced schema are one stream', () {
      final fixture = IrFixture(
        _spec(
          r'''
  /same:
    get:
      operationId: same
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {$ref: '#/components/schemas/Tick'}}}}
        "201": {description: made, content: {text/event-stream: {schema: {$ref: '#/components/schemas/Tick'}}}}
''',
          schemas: '{Tick: {type: object, properties: {n: {type: integer}}}}',
        ),
      );
      final ir = fixture.build();
      expect(_names(ir), ['same']);
      expect(_declared(ir), ['Tick']);
      expect(fixture.reportedOf(.eventStreamNotGenerated), isEmpty);
    });

    test('with one referenced union itemSchema are one stream and union', () {
      final fixture = IrFixture(
        _spec(
          r'''
  /same:
    get:
      operationId: same
      responses:
        "200": {description: ok, content: {text/event-stream: {itemSchema: {$ref: '#/components/schemas/Events'}}}}
        "201": {description: made, content: {text/event-stream: {itemSchema: {$ref: '#/components/schemas/Events'}}}}
''',
          schemas: '''
{Events: {oneOf: [
  {type: object, properties: {event: {const: a}, data: {type: string}}},
  {type: object, properties: {event: {const: b}}}]}}''',
        ),
      );
      final ir = fixture.build();
      expect(_names(ir), ['same']);
      final union = ir.groups.single.operations.single.events!.union;
      expect([for (final v in union!.variants) v.event], ['a', 'b']);
      expect(fixture.reportedOf(.eventStreamNotGenerated), isEmpty);
      expect(fixture.reportedOf(.nameCollision), isEmpty);
    });
  });

  group('event streams with different event types (TOA654)', () {
    test('leave no declaration of either schema', () {
      final fixture = IrFixture(
        _spec('''
  /e:
    get:
      operationId: e
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: object, properties: {a: {type: string}}}}}}
        "201": {description: made, content: {text/event-stream: {schema: {type: object, properties: {b: {type: integer}}}}}}
'''),
      );
      final ir = fixture.build();
      expect(ir.groups, isEmpty);
      expect(_declared(ir), isEmpty);
      expect(fixture.reportedOf(.eventStreamNotGenerated), hasLength(1));
      expect(fixture.reportedOf(.nameCollision), isEmpty);
    });

    test('of the stream method alone leave the JSON method, and report '
        'nothing else', () {
      final fixture = IrFixture(
        _spec(
          r'''
  /a:
    get:
      operationId: a
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {$ref: '#/components/schemas/Reply'}}
            text/event-stream: {schema: {type: object, properties: {x: {type: string}}}}
        "201":
          description: made
          content:
            application/json: {schema: {$ref: '#/components/schemas/Reply'}}
            text/event-stream: {schema: {type: object, properties: {y: {type: integer}}}}
  /a-stream:
    get:
      operationId: aStream
      responses:
        "204": {description: none}
''',
          schemas: '{Reply: {type: object, properties: {r: {type: string}}}}',
        ),
      );
      final ir = fixture.build();
      expect(_names(ir), ['a', 'aStream']);
      expect(_declared(ir), ['Reply']);
      expect(
        fixture.reportedOf(.eventStreamNotGenerated).single.pointer?.value,
        '#/paths/~1a/get/responses',
      );
      expect(fixture.reportedOf(.eventStreamMethodAdded), isEmpty);
      expect(fixture.reportedOf(.nameCollision), isEmpty);
    });
  });
}
