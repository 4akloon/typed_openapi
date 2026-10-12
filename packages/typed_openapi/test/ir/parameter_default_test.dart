import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

/// The parameters of a spec of OpenAPI [version] with one operation whose
/// parameters are [parameters] (YAML list items) and the schemas [schemas].
List<ParameterIr> parametersOf(
  String version,
  String parameters, {
  String schemas = '',
}) {
  final fixture = IrFixture('''
openapi: $version
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: list
      tags: [t]
      parameters:
$parameters
      responses: {"200": {description: ok}}
components:
  schemas:
    Order: {type: string, enum: [asc, desc], default: asc}
$schemas
''');
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return ir.groups.single.operations.single.parameters;
}

/// The default of the only parameter written as [schema] in a query.
Object? defaultOf(String version, String schema, {String schemas = ''}) {
  final parameters = parametersOf(
    version,
    '        - {name: p, in: query, schema: $schema}',
    schemas: schemas,
  );
  return parameters.single.defaultValue?.$1;
}

void main() {
  const ref = r"{$ref: '#/components/schemas/Order'";

  group('a default beside a reference', () {
    test('wins in OpenAPI 3.1', () {
      expect(defaultOf('3.1.0', '$ref, default: desc}'), 'desc');
    });

    test('is ignored in OpenAPI 3.0, which has no siblings of a reference', () {
      expect(defaultOf('3.0.3', '$ref, default: desc}'), 'asc');
    });

    test('is not needed: the target gives its own', () {
      expect(defaultOf('3.1.0', '$ref}'), 'asc');
      expect(defaultOf('3.0.3', '$ref}'), 'asc');
    });
  });

  group('a default through a wrapper of a reference', () {
    test('an allOf with one reference takes the target default', () {
      expect(defaultOf('3.1.0', '{allOf: [$ref}]}'), 'asc');
      expect(defaultOf('3.0.3', '{allOf: [$ref}]}'), 'asc');
    });

    test('a default of the wrapper comes first', () {
      expect(defaultOf('3.1.0', '{allOf: [$ref}], default: desc}'), 'desc');
      expect(defaultOf('3.0.3', '{allOf: [$ref}], default: desc}'), 'desc');
    });

    test('a nullable anyOf takes the target default', () {
      expect(
        defaultOf('3.1.0', "{anyOf: [$ref}, {type: 'null'}]}"),
        'asc',
      );
    });

    test('a nullable oneOf takes the target default', () {
      expect(
        defaultOf('3.1.0', "{oneOf: [$ref}, {type: 'null'}]}"),
        'asc',
      );
    });

    test('a sibling default of the branch wins in 3.1 and not in 3.0', () {
      expect(
        defaultOf('3.1.0', "{anyOf: [$ref, default: desc}, {type: 'null'}]}"),
        'desc',
      );
      expect(
        defaultOf('3.0.3', "{anyOf: [$ref, default: desc}, {type: 'null'}]}"),
        'asc',
      );
    });

    test('a wrapper of a schema without a default has none', () {
      expect(
        defaultOf('3.1.0', "{anyOf: [{type: string}, {type: 'null'}]}"),
        isNull,
      );
    });
  });

  group('a parameter default', () {
    test('is kept for header and cookie parameters', () {
      final parameters = parametersOf(
        '3.1.0',
        r'''
        - {name: X-Page, in: header, schema: {type: integer, default: 3}}
        - {name: session, in: cookie, schema: {type: string, default: anon}}
        - {name: mode, in: header, schema: {$ref: '#/components/schemas/Order'}}''',
      );
      expect(
        [for (final p in parameters) (p.wireName, p.defaultValue?.$1)],
        [('X-Page', 3), ('mode', 'asc'), ('session', 'anon')],
      );
    });

    test('is kept for a parameter that has content', () {
      final parameters = parametersOf('3.1.0', '''
        - name: filter
          in: query
          content:
            application/json:
              schema: {type: object, default: {a: 1}}''');
      expect(parameters.single.defaultValue?.$1, {'a': 1});
    });

    test('is kept as a list, an object and null', () {
      expect(
        defaultOf(
          '3.1.0',
          '{type: array, items: {type: integer}, default: [1, 2]}',
        ),
        [1, 2],
      );
      expect(
        defaultOf('3.1.0', '{type: object, default: {a: b}}'),
        {'a': 'b'},
      );
      final withNull = parametersOf(
        '3.1.0',
        "        - {name: p, in: query, schema: {type: [string, 'null'], default: null}}",
      );
      expect(withNull.single.defaultValue, (null,));
    });

    test('is absent when no schema in the chain has one', () {
      final parameters = parametersOf(
        '3.1.0',
        '        - {name: p, in: query, schema: {type: string}}',
      );
      expect(parameters.single.defaultValue, isNull);
    });
  });
}
