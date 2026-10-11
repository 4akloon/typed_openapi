import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/parse_context.dart';
import 'package:typed_openapi/src/resolve/ref_resolver.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';
import 'package:typed_openapi/src/resolve/spec_model.dart';

import '../helpers/temp_dir.dart';

void main() {
  late TempDir dir;

  setUp(() => dir = TempDir());

  (SpecModel, DiagnosticBag) resolve(String rootFile) {
    final bag = DiagnosticBag();
    final loader = SpecLoader(bag);
    final root = loader.load(
      p.join(dir.path, rootFile),
      displayPath: rootFile,
    )!;
    final index = SpecIndex();
    final document = OpenApiParser(bag, root, index).parse(.v31);
    final model = RefResolver(
      bag,
    ).resolve(document, index, SpecDocuments(loader, root));
    return (model, bag);
  }

  const info = 'openapi: 3.1.0\ninfo: {title: t, version: "1"}';

  test('resolves local references, through aliases', () {
    dir.write('api.yaml', '''
$info
paths:
  /pets:
    get:
      parameters: [{\$ref: "#/components/parameters/Limit"}]
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema: {\$ref: "#/components/schemas/Pets"}
components:
  parameters:
    Limit: {\$ref: "#/components/parameters/PageSize"}
    PageSize: {name: size, in: query}
  schemas:
    Pets: {type: array, items: {\$ref: "#/components/schemas/Pet"}}
    Pet: {type: object}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/pets']!)!;
    final parameter = model.resolve(get.operations['get']!.parameters.single);
    expect(parameter!.name, 'size');
    final pets = model.document.components!.schemas['Pets']! as SchemaObject;
    final pet = model.resolveSchema(pets.items!)! as SchemaObject;
    expect(pet.pointer.value, '#/components/schemas/Pet');
    expect(model.targetOf(pets.items!.location), pet.location);
  });

  test('a recursive schema is not a problem', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Node:
      type: object
      properties:
        children: {type: array, items: {\$ref: "#/components/schemas/Node"}}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final node = model.document.components!.schemas['Node']! as SchemaObject;
    final children = node.properties['children']! as SchemaObject;
    expect(model.resolveSchema(children.items!), same(node));
  });

  test('a reference to nothing is unresolved', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner: {\$ref: "#/components/schemas/Person"}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/$ref');
    expect(d.line, 5);
    final owner = model.document.components!.schemas['Owner']!;
    expect(model.resolveSchema(owner), isNull);
  });

  test('an empty name is invalid and reported where it is written', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner:
      properties:
        pet: {\$ref: "#/components/schemas/"}
''');
    final (_, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.invalidRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/properties/pet/$ref');
    expect(d.file, 'api.yaml');
  });

  test('follows references into other files, keyed by file and pointer', () {
    dir.write('specs/api.yaml', '''
$info
components:
  schemas:
    Error: {\$ref: "common/errors.yaml#/components/schemas/Error"}
''');
    dir.write('specs/common/errors.yaml', r'''
components:
  schemas:
    Error:
      type: object
      properties:
        code: {$ref: "codes.yaml#/Code"}
        extra: {$ref: "#/components/schemas/Missing"}
''');
    dir.write('specs/common/codes.yaml', 'Code: {type: string}\n');
    final (model, bag) = resolve('specs/api.yaml');
    final local = model.document.components!.schemas['Error']!;
    final remote = model.resolveSchema(local)! as SchemaObject;
    expect(remote.location, isNot(local.location));
    expect(remote.pointer, local.pointer);
    expect(
      remote.location.document,
      p.toUri(p.join(dir.path, 'specs', 'common', 'errors.yaml')),
    );
    final code = model.resolveSchema(remote.properties['code']!)!;
    expect((code as SchemaObject).types, [SchemaType.string]);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.file, p.join('specs', 'common', 'errors.yaml'));
    expect(d.line, 7);
  });

  test('a missing file and a remote URL are reported', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "missing.yaml#/A"}
    B: {\$ref: "https://example.com/b.yaml"}
''');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.unresolvedRef,
      DiagnosticCode.remoteRef,
    ]);
    expect(
      bag.all.first.message,
      '"missing.yaml#/A" points to missing.yaml, which does not exist or '
      'cannot be read.',
    );
  });

  test('a file referenced many times is read once', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "broken.yaml#/A"}
    B: {\$ref: "broken.yaml#/B"}
''');
    dir.write('broken.yaml', 'A: [\n');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.parseError, 'broken.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
    ]);
  });

  test('a reference to a node of another kind is reported', () {
    dir.write('api.yaml', '''
$info
paths:
  /a:
    get:
      parameters: [{\$ref: "#/components/schemas/Limit"}]
components:
  schemas:
    Limit: {type: integer}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.refKindMismatch);
    expect(
      d.message,
      '"#/components/schemas/Limit" points to a schema, but a parameter is '
      'expected here.',
    );
    final get = model.resolve(model.document.paths['/a']!)!;
    expect(model.resolve(get.operations['get']!.parameters.single), isNull);
  });

  test('a target outside components is read as the expected kind', () {
    dir.write('api.yaml', '''
$info
x-shared:
  limit: {name: limit, in: query}
paths:
  /a:
    get:
      parameters: [{\$ref: "#/x-shared/limit"}]
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/a']!)!;
    final limit = model.resolve(get.operations['get']!.parameters.single);
    expect(limit!.name, 'limit');
    expect(model.nodeAt(limit.location), same(limit));
  });

  test('a malformed target is parsed and reported once', () {
    dir.write('api.yaml', '''
$info
x-shared:
  limit: oops
paths:
  /a:
    get:
      parameters:
        - {\$ref: "#/x-shared/limit"}
        - {\$ref: "#/x-shared/limit"}
''');
    final (_, bag) = resolve('api.yaml');
    final reports = bag.all.where((d) => d.code == DiagnosticCode.invalidValue);
    expect(reports.map((d) => d.pointer?.value), ['#/x-shared/limit']);
  });
}
