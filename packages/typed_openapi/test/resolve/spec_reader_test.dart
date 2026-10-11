import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  test('parses, resolves and checks the dialect in one call', () {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(r'''
openapi: 3.0.3
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {tag: {$ref: "#/components/schemas/Tag"}}}
    Tag: {type: [string, "null"]}
''', 'api.yaml')!;
    final model = SpecReader(bag).read(document, .v30);
    final pet = model.document.components!.schemas['Pet']! as SchemaObject;
    final tag = model.resolveSchema(pet.properties['tag']!)! as SchemaObject;
    expect(tag.types, [SchemaType.string, SchemaType.nullType]);
    expect(model.document.version, OpenApiVersion.v30);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.openApi31InOpenApi30,
      DiagnosticCode.openApi31InOpenApi30,
    ]);
  });

  test('a schema nested as deep as the loader allows is read', () {
    final bag = DiagnosticBag();
    const depth = NestingScanner.maxDepth - 4;
    final schema = '${'{"items": ' * depth}{"type": "string"}${'}' * depth}';
    final document = SpecLoader(bag).parse(
      '{"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, '
          '"components": {"schemas": {"Deep": $schema}}}',
      'api.json',
    )!;
    final model = SpecReader(bag).read(document, .v31);
    var current = model.document.components!.schemas['Deep'];
    var levels = 0;
    while (current is SchemaObject && current.items != null) {
      current = current.items;
      levels++;
    }
    expect(levels, depth);
    expect(bag.all, isEmpty);
  });
}
