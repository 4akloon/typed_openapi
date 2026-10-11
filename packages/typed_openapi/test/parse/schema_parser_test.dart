import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/schema_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (Schema?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('schema');
    final schema = SchemaParser(
      fixture.context,
    ).parse(fixture.document.valueAt(pointer)!.$1, pointer);
    return (schema, fixture);
  }

  test('reads a 3.0 object schema', () {
    final (schema, fixture) = parse('''
schema:
  type: object
  required: [id]
  nullable: true
  description: A pet.
  properties:
    id: {type: integer, format: int64, minimum: 1}
    tags: {type: array, items: {type: string}, maxItems: 10}
  additionalProperties: false
  x-order: 3
''');
    final pet = schema! as SchemaObject;
    expect(pet.types, [SchemaType.object]);
    expect(pet.required, ['id']);
    expect(pet.nullable, isTrue);
    expect(pet.description, 'A pet.');
    expect(pet.properties.keys, ['id', 'tags']);
    final id = pet.properties['id']! as SchemaObject;
    expect(id.format, 'int64');
    expect(id.minimum, 1);
    final tags = pet.properties['tags']! as SchemaObject;
    expect((tags.items! as SchemaObject).types, [SchemaType.string]);
    expect(tags.maxItems, 10);
    expect((pet.additionalProperties! as BooleanSchema).value, isFalse);
    expect(pet.extensions, {'x-order': 3});
    expect(pet.pointer.value, '#/schema');
    expect(id.pointer.value, '#/schema/properties/id');
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature), [
      SpecFeature.nullable,
    ]);
  });

  test('reads 2020-12 keywords and notes them as 3.1 constructs', () {
    final (schema, fixture) = parse(r'''
schema:
  type: [string, "null"]
  const: a
  examples: [a]
  exclusiveMinimum: 0
  prefixItems: [true]
  contentMediaType: application/json
  contentSchema: {type: object}
  $defs: {Id: {type: string}}
''');
    final s = schema! as SchemaObject;
    expect(s.types, [SchemaType.string, SchemaType.nullType]);
    expect(s.constValue, ('a',));
    expect(s.examples, ['a']);
    expect(s.exclusiveMinimum, 0);
    expect(s.exclusiveMinimumFlag, isNull);
    expect(s.prefixItems.single, isA<BooleanSchema>());
    expect(s.contentSchema, isA<SchemaObject>());
    expect(s.otherKeywords.keys, [r'$defs']);
    expect(fixture.diagnostics.all, isEmpty);
    expect(
      fixture.index.features.map((f) => f.feature).toSet(),
      {
        SpecFeature.typeList,
        SpecFeature.nullType,
        SpecFeature.constKeyword,
        SpecFeature.schemaExamples,
        SpecFeature.numericExclusiveBound,
        SpecFeature.prefixItems,
        SpecFeature.booleanSchema,
        SpecFeature.contentKeywords,
        SpecFeature.jsonSchemaKeyword,
      },
    );
  });

  test('keeps a boolean exclusive bound as the 3.0 flag', () {
    final (schema, fixture) = parse(
      'schema: {maximum: 5, exclusiveMaximum: true}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.exclusiveMaximumFlag, isTrue);
    expect(s.exclusiveMaximum, isNull);
    expect(fixture.index.features, isEmpty);
  });

  test(r'keeps $ref with its siblings and records the reference', () {
    final (schema, fixture) = parse(
      'schema: {\$ref: "#/components/schemas/Pet", description: Owner.}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.ref, '#/components/schemas/Pet');
    expect(s.description, 'Owner.');
    final use = fixture.index.refs.single;
    expect(use.ref, '#/components/schemas/Pet');
    expect(use.kind, RefKind.schema);
    expect(use.site, s.location);
  });

  test('defaults, null enum members and examples are kept as written', () {
    final (schema, _) = parse(
      'schema: {default: null, enum: [a, null], example: {k: 1}}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.defaultValue, (null,));
    expect(s.enumValues, ['a', null]);
    expect(s.example?.$1, {'k': 1});
  });

  test('a boolean "required" and an unknown type are reported, the rest is '
      'read', () {
    final (schema, fixture) = parse('''
schema:
  type: array
  items:
    type: file
    required: true
    format: binary
''');
    final items = (schema! as SchemaObject).items! as SchemaObject;
    expect(items.types, isEmpty);
    expect(items.required, isEmpty);
    expect(items.format, 'binary');
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/schema/items/type',
      '#/schema/items/required',
    ]);
  });

  test('reads a discriminator with a 3.2 defaultMapping', () {
    final (schema, fixture) = parse(r'''
schema:
  oneOf: [{$ref: "#/c/Cat"}, {$ref: "#/c/Dog"}]
  discriminator:
    propertyName: kind
    mapping: {cat: "#/c/Cat"}
    defaultMapping: "#/c/Dog"
''');
    final d = (schema! as SchemaObject).discriminator!;
    expect(d.propertyName, 'kind');
    expect(d.mapping, {'cat': '#/c/Cat'});
    expect(d.defaultMapping, '#/c/Dog');
    expect(fixture.index.refs, hasLength(2));
    expect(fixture.index.features.single.feature, SpecFeature.defaultMapping);
  });

  test('reports a schema that is neither an object nor a boolean', () {
    final (schema, fixture) = parse('schema: [a]\n');
    expect(schema, isNull);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
  });

  test(r'reports $id: refs inside are not resolved against it', () {
    final (_, fixture) = parse('schema: {\$id: "https://example.com/a"}\n');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
  });

  test('registers every schema by location', () {
    final (schema, fixture) = parse(
      'schema: {properties: {a: {items: {type: string}}}}\n',
    );
    expect(fixture.index.nodes.values, hasLength(3));
    expect(fixture.index.nodes[schema!.location], same(schema));
  });
}
