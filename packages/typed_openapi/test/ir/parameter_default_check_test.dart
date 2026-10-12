import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/ir_fixture.dart';

IrFixture _fixture(String schema, {String schemas = ''}) => IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: list
      tags: [t]
      parameters:
        - {name: p, in: query, schema: $schema}
      responses: {"200": {description: ok}}
components:
  schemas:
    Order: {type: string, enum: [asc, desc]}
$schemas
''');

void main() {
  group('a default that does not match its schema', () {
    for (final (name, schema) in <(String, String)>[
      ('an enum', '{type: string, enum: [asc, desc], default: sideways}'),
      ('an integer enum', '{type: integer, enum: [1, 2], default: 3}'),
      ('a date', '{type: string, format: date, default: tomorrow}'),
      (
        'a date-time without an offset',
        '{type: string, format: date-time, default: "2020-01-01T00:00:00"}',
      ),
      ('a uuid', '{type: string, format: uuid, default: abc}'),
      (
        'an int32 out of range',
        '{type: integer, format: int32, default: 3000000000}',
      ),
      (
        'a referenced enum',
        r"{$ref: '#/components/schemas/Order', default: sideways}",
      ),
    ]) {
      test('$name is reported and not documented', () {
        final fixture = _fixture(schema);
        final parameter = fixture
            .build()
            .groups
            .single
            .operations
            .single
            .parameters
            .single;
        expect(parameter.defaultValue, isNull);
        final [warning] = fixture.reportedOf(.defaultValueInvalid);
        expect(warning.severity, Severity.warning);
        expect(warning.pointer?.value, endsWith('/default'));
        expect(warning.message, contains('default'));
      });
    }

    test('is not reported when it matches', () {
      for (final schema in [
        '{type: string, enum: [asc, desc], default: desc}',
        '{type: integer, enum: [1, 2], default: 2}',
        '{type: string, format: date, default: "2020-02-29"}',
        '{type: string, format: date-time, default: "2020-01-01T00:00:00Z"}',
        '{type: string, format: uuid, default: "123e4567-e89b-12d3-a456-426614174000"}',
        '{type: integer, format: int32, default: 7}',
        '{type: string, format: email, default: nobody}',
        r"{$ref: '#/components/schemas/Order', default: desc}",
      ]) {
        final fixture = _fixture(schema);
        final parameter = fixture
            .build()
            .groups
            .single
            .operations
            .single
            .parameters
            .single;
        expect(parameter.defaultValue, isNotNull, reason: schema);
        expect(fixture.reportedOf(.defaultValueInvalid), isEmpty);
      }
    });
  });
}
