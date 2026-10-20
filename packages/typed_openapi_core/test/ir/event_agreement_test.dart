import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose `GET /multi` has the event-stream successes 200 and 201;
/// [first] and [second] are the YAML of their media types.
String _spec(String first, String second) =>
    '''
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
            text/event-stream: $first
        "201":
          description: ok
          content:
            text/event-stream; charset=utf-8: $second
components:
  schemas:
    E: {type: object, properties: {part: {type: string}}}
''';

/// The IR of [first] and [second] and its fixture.
(List<OperationIr>, IrFixture) _build(String first, String second) {
  final fixture = IrFixture(_spec(first, second));
  final ir = fixture.build();
  return ([for (final g in ir.groups) ...g.operations], fixture);
}

/// Expects one stream method and no TOA654 for [first] and [second].
void _expectAgree(String first, String second) {
  final (methods, fixture) = _build(first, second);
  expect([for (final m in methods) m.name], ['multi']);
  expect(fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated), isEmpty);
  expect(fixture.reportedOf(DiagnosticCode.nameCollision), isEmpty);
}

void main() {
  group('two event-stream successes with the same event type', () {
    test('written with an infinite number in an inline schema', () {
      _expectAgree(
        '{schema: {type: number, minimum: .inf, maximum: .nan}}',
        '{schema: {type: number, minimum: .inf, maximum: .nan}}',
      );
    });

    test('with and without an annotation', () {
      _expectAgree(
        '{schema: {type: string}}',
        '{schema: {type: string, description: x, title: T, example: y}}',
      );
    });

    test('as arrays whose items differ in an annotation', () {
      _expectAgree(
        '{schema: {type: array, items: {type: string}}}',
        '{schema: {type: array, items: {type: string, description: x}}}',
      );
    });

    test('as objects whose nested property differs in an annotation', () {
      _expectAgree(
        '{schema: {type: object, properties: {a: {type: object, '
            'properties: {b: {type: integer}}}}}}',
        '{schema: {type: object, properties: {a: {type: object, '
            'properties: {b: {type: integer, title: B}}, description: A}}}}',
      );
    });

    test('as an itemSchema whose data has a description', () {
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
            text/event-stream; charset=utf-8:
              itemSchema: {properties: {data: {type: string, description: x}}}
''',
      );
      expect([
        for (final g in fixture.build().groups) ...g.operations,
      ], hasLength(1));
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });

    test('as a string and as a type list with null', () {
      _expectAgree(
        '{schema: {type: string}}',
        "{schema: {type: [string, 'null']}}",
      );
    });

    test('as a nullable list of an object and the object', () {
      _expectAgree(
        '{schema: {type: object, properties: {a: {type: integer}}}}',
        '{schema: {type: [object, "null"], '
            'properties: {a: {type: [integer, "null"]}}}}',
      );
    });

    test('as text and as a nullable string', () {
      _expectAgree('{}', "{schema: {type: [string, 'null']}}");
    });

    test('as a string schema and as no schema at all', () {
      _expectAgree('{schema: {type: string}}', '{}');
    });

    test('with a format and an annotation', () {
      _expectAgree(
        '{schema: {type: integer, format: int64}}',
        '{schema: {type: integer, format: int64, description: x}}',
      );
    });

    test('as a reference and as an allOf of that reference', () {
      _expectAgree(
        r"{schema: {$ref: '#/components/schemas/E'}}",
        r"{schema: {allOf: [{$ref: '#/components/schemas/E'}]}}",
      );
    });

    test('as a reference and as an annotated allOf of it', () {
      _expectAgree(
        r"{schema: {$ref: '#/components/schemas/E'}}",
        r"{schema: {description: d, allOf: [{$ref: '#/components/schemas/E'}]}}",
      );
    });
  });

  group('two event-stream successes with different event types', () {
    test('a string and an object are TOA654', () {
      final (methods, fixture) = _build(
        '{schema: {type: string}}',
        '{schema: {type: object, properties: {a: {type: string}}}}',
      );
      expect(methods, isEmpty);
      expect(fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated), [
        isNotNull,
      ]);
    });

    test('two scalars with other formats are TOA654', () {
      final (methods, fixture) = _build(
        '{schema: {type: integer, format: int32}}',
        '{schema: {type: integer, format: int64}}',
      );
      expect(methods, isEmpty);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        hasLength(1),
      );
    });

    test('arrays whose items have other types are TOA654', () {
      final (methods, _) = _build(
        '{schema: {type: array, items: {type: string}}}',
        '{schema: {type: array, items: {type: integer, description: x}}}',
      );
      expect(methods, isEmpty);
    });

    test('a property that is named like an annotation still counts', () {
      final (methods, _) = _build(
        '{schema: {type: object, properties: {description: {type: string}}}}',
        '{schema: {type: object, properties: {description: {type: integer}}}}',
      );
      expect(methods, isEmpty);
    });

    test('a property that one has and the other lacks is TOA654', () {
      final (methods, _) = _build(
        '{schema: {type: object, properties: {a: {type: string}}}}',
        '{schema: {type: object, properties: {a: {type: string}, b: {type: string}}}}',
      );
      expect(methods, isEmpty);
    });

    test('text and a number are TOA654', () {
      final (methods, _) = _build('{}', '{schema: {type: number}}');
      expect(methods, isEmpty);
    });
  });
}
