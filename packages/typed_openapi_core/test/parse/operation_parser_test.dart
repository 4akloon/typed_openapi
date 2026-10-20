import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/model/operation.dart';
import 'package:typed_openapi_core/src/model/schema.dart';
import 'package:typed_openapi_core/src/model/spec_node.dart';
import 'package:typed_openapi_core/src/parse/operation_parser.dart';
import 'package:typed_openapi_core/src/parse/schema_parser.dart';
import 'package:typed_openapi_core/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (RefOr<PathItem>?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('item');
    final item = OperationParser(
      fixture.context,
      SchemaParser(fixture.context),
    ).pathItem(fixture.document.valueAt(pointer)!.$1, pointer);
    return (item, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a path item with an operation', () {
    final (item, fixture) = parse(r'''
item:
  parameters:
    - {name: id, in: path, required: true, schema: {type: string}}
  get:
    operationId: getPet
    tags: [pets]
    parameters:
      - $ref: "#/components/parameters/Limit"
    responses:
      "200":
        description: OK
        headers:
          X-Rate: {schema: {type: integer}}
        content:
          application/json:
            schema: {$ref: "#/components/schemas/Pet"}
      default: {$ref: "#/components/responses/Error"}
      x-codegen: skip
    security: []
''');
    final pets = inline(item);
    expect(pets.parameters, hasLength(1));
    final id = inline(pets.parameters.single);
    expect(id.name, 'id');
    expect(id.placement, ParameterLocation.path);
    expect(id.required, isTrue);
    final get = pets.operations['get']!;
    expect(get.operationId, 'getPet');
    expect(get.tags, ['pets']);
    expect(get.parameters.single, isA<Ref<Parameter>>());
    expect(get.responses.keys, ['200', 'default']);
    final ok = inline(get.responses['200']);
    expect(ok.description, 'OK');
    expect(inline(ok.headers['X-Rate']).schema, isA<SchemaObject>());
    final json = inline(ok.content['application/json']);
    expect((json.schema! as SchemaObject).ref, '#/components/schemas/Pet');
    expect(get.security, isEmpty);
    expect(pets.operations['post'], isNull);
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.refs.map((r) => (r.ref, r.kind)), [
      ('#/components/parameters/Limit', RefKind.parameter),
      ('#/components/schemas/Pet', RefKind.schema),
      ('#/components/responses/Error', RefKind.response),
    ]);
  });

  test('a malformed security requirement value keeps the scheme, empty', () {
    final (item, fixture) = parse('''
item:
  get:
    responses: {}
    security:
      - oauth: [read]
        broken: write
        mixed: [a, 1]
''');
    final requirement = inline(item).operations['get']!.security!.single;
    expect(requirement.schemes, {
      'oauth': ['read'],
      'broken': <String>[],
      'mixed': ['a'],
    });
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/item/get/security/0/broken',
      '#/item/get/security/0/mixed/1',
    ]);
  });

  test('a node inside an already read parameter is the same node', () {
    final (item, fixture) = parse('''
item:
  parameters:
    - {name: id, in: path, schema: {type: string}, bogus: 1}
''');
    final parameters = inline(item).parameters;
    final pointer = JsonPointer.parse('#/item/parameters/0');
    final again = OperationParser(
      fixture.context,
      SchemaParser(fixture.context),
    ).parameter(fixture.document.valueAt(pointer)!.$1, pointer);
    expect(inline(again), same(inline(parameters.single)));
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
    expect(fixture.index.nodes, hasLength(3));
  });

  test('a security field that is not a list is one malformed requirement', () {
    final (item, fixture) = parse('''
item:
  get:
    responses: {}
    security: {bearer: []}
''');
    final requirement = inline(item).operations['get']!.security!.single;
    expect(requirement.isMalformed, isTrue);
    expect(requirement.isNotList, isTrue);
    expect(requirement.location.pointer.value, '#/item/get/security');
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
    expect(fixture.pointers, ['#/item/get/security']);
  });

  test('security stays null when an operation does not set it', () {
    final (item, _) = parse('item: {get: {responses: {}}}\n');
    expect(inline(item).operations['get']!.security, isNull);
  });

  test('reads request bodies, encodings and examples', () {
    final (item, fixture) = parse('''
item:
  post:
    requestBody:
      required: true
      content:
        multipart/form-data:
          schema: {type: object}
          encoding:
            file: {contentType: image/png}
          examples:
            one: {summary: One, value: {a: 1}}
''');
    final body = inline(inline(item).operations['post']!.requestBody);
    expect(body.required, isTrue);
    final form = inline(body.content['multipart/form-data']);
    expect(form.encoding['file']!.contentType, 'image/png');
    expect(inline(form.examples['one']).summary, 'One');
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('reads 3.2 constructs and notes them', () {
    final (item, fixture) = parse('''
item:
  query:
    parameters:
      - {name: filter, in: querystring, content: {application/x-www-form-urlencoded: {}}}
    responses:
      "200":
        summary: Events
        content:
          text/event-stream:
            itemSchema: {type: object}
  additionalOperations:
    PURGE: {responses: {}}
''');
    final pets = inline(item);
    expect(pets.operations.keys, ['query']);
    expect(pets.additionalOperations.keys, ['PURGE']);
    final query = pets.operations['query']!;
    expect(
      inline(query.parameters.single).placement,
      ParameterLocation.querystring,
    );
    final events = inline(
      inline(query.responses['200']).content['text/event-stream'],
    );
    expect(events.itemSchema, isA<SchemaObject>());
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.queryOperation,
      SpecFeature.querystringParameter,
      SpecFeature.responseSummary,
      SpecFeature.itemSchema,
      SpecFeature.additionalOperations,
    });
  });

  test('a Swagger 2 style parameter is reported, the rest is read', () {
    final (item, fixture) = parse('''
item:
  get:
    parameters:
      - {name: limit, in: query, type: integer}
      - {in: header, schema: {type: string}}
      - {name: x, in: body}
''');
    final params = inline(item).operations['get']!.parameters;
    expect(params.map((p) => inline(p).name), ['limit', null, 'x']);
    expect(fixture.codes, [
      DiagnosticCode.unknownKey,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/item/get/parameters/0/type',
      '#/item/get/parameters/1',
      '#/item/get/parameters/2/in',
    ]);
  });

  test('a Reference Object keeps summary and description and reports the '
      'rest', () {
    final (item, fixture) = parse(r'''
item:
  $ref: "#/components/pathItems/Pets"
  description: Pets.
  get: {}
''');
    final ref = item! as Ref<PathItem>;
    expect(ref.ref, '#/components/pathItems/Pets');
    expect(ref.description, 'Pets.');
    expect(ref.kind, RefKind.pathItem);
    expect(ref.unknownKeys.keys, ['get']);
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
  });

  test('a node of the wrong shape is reported and skipped', () {
    final (item, fixture) = parse('item: {get: {responses: {"200": oops}}}\n');
    expect(inline(item).operations['get']!.responses, isEmpty);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
    expect(
      fixture.diagnostics.all.single.message,
      'This response must be an object, not a string.',
    );
  });
}
