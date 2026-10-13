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
      for (final (reason, format, value) in <(String, String, String)>[
        ('a date with month 13', 'date', '2020-13-01'),
        ('a date with day 32', 'date', '2020-01-32'),
        ('a date with day 0', 'date', '2020-01-00'),
        ('a date of 29 February in a non-leap year', 'date', '2021-02-29'),
        ('a date-time with month 13', 'date-time', '2020-13-01T00:00:00Z'),
        ('a date-time with month 0', 'date-time', '2020-00-01T00:00:00Z'),
        ('a date-time with day 32', 'date-time', '2020-01-32T00:00:00Z'),
        ('a date-time of 30 February', 'date-time', '2020-02-30T00:00:00Z'),
        ('a date-time of 31 April', 'date-time', '2020-04-31T00:00:00Z'),
        (
          'a date-time of 29 February in a non-leap year',
          'date-time',
          '2021-02-29T00:00:00Z',
        ),
        (
          'a date-time of 29 February 1900 (no leap year)',
          'date-time',
          '1900-02-29T00:00:00Z',
        ),
        ('a date-time with hour 24', 'date-time', '2020-01-01T24:00:00Z'),
        ('a date-time with minute 60', 'date-time', '2020-01-01T00:60:00Z'),
        ('a date-time with second 61', 'date-time', '2020-01-01T00:00:61Z'),
        (
          'a date-time with an offset hour 24',
          'date-time',
          '2020-01-01T00:00:00+24:00',
        ),
        (
          'a date-time with an offset minute 60',
          'date-time',
          '2020-01-01T00:00:00-01:60',
        ),
      ])
        (reason, '{type: string, format: $format, default: "$value"}'),
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
        // RFC 3339 allows a lower-case `t` and `z`.
        '{type: string, format: date-time, default: "2020-01-01t00:00:00z"}',
        '{type: string, format: date-time, default: "2020-01-01t00:00:00.5+02:00"}',
        '{type: string, format: date, default: "2000-02-29"}',
        '{type: string, format: date-time, default: "2000-02-29T23:59:59Z"}',
        '{type: string, format: date-time, default: "2020-12-31T23:59:60Z"}',
        '{type: string, format: date-time, default: "2020-04-30T00:00:00-23:59"}',
        '{type: string, format: date-time, default: "2020-04-30t00:00:00+05:30"}',
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
