import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  const pets = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/Dog'}
      discriminator:
        propertyName: kind
        mapping:
          cat: '#/components/schemas/Cat'
          dog: Dog
          bird: '#/components/schemas/Bird'
          fish: Fish
    Base:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
    Cat:
      allOf: [{$ref: '#/components/schemas/Base'}]
    Dog:
      type: object
      properties: {kind: {type: string}}
''';

  test('discriminator-property-required: once per discriminator, through '
      'allOf', () {
    final d = NormalizerFixture(pets).of(
      DiagnosticCode.discriminatorNotRequired,
    );
    expect(d.single.pointer?.value, '#/components/schemas/Pet/discriminator');
    expect(d.single.severity, Severity.info);
    expect(
      d.single.message,
      'Discriminator property "kind" is not required in Dog; a payload '
      'without it cannot be told apart.',
    );
  });

  test('discriminator-property-required lists at most ten variants', () {
    final schemas = StringBuffer();
    final refs = StringBuffer();
    for (var i = 0; i < 12; i++) {
      final name = 'V${i.toString().padLeft(2, '0')}';
      schemas.writeln('    $name: {type: object}');
      refs.writeln("        - {\$ref: '#/components/schemas/$name'}");
    }
    final d = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      discriminator: {propertyName: kind}
      oneOf:
$refs$schemas''').of(DiagnosticCode.discriminatorNotRequired);
    expect(
      d.single.message,
      'Discriminator property "kind" is not required in V00, V01, V02, V03, '
      'V04, V05, V06, V07, V08, V09 and 2 more; a payload without it cannot '
      'be told apart.',
    );
  });

  test('discriminator-mapping-target: names and references', () {
    final d = NormalizerFixture(pets).of(
      DiagnosticCode.discriminatorMappingUnresolved,
    );
    expect(d.map((d) => d.pointer?.value), [
      '#/components/schemas/Pet/discriminator/mapping/bird',
      '#/components/schemas/Pet/discriminator/mapping/fish',
    ]);
    expect(d.first.severity, Severity.error);
    expect(
      d.first.message,
      'discriminator.mapping "bird" points to '
      '"#/components/schemas/Bird", which does not exist.',
    );
  });

  test('wildcard-media-type in a response; springdoc gets the property', () {
    final run = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: list
      responses:
        "200":
          description: ok
          content:
            "*/*": {schema: {type: string}}
            application/json: {schema: {type: string}}
''', preset: .springdoc);
    final d = run.of(DiagnosticCode.wildcardMediaType).single;
    expect(d.pointer?.value, '#/paths/~1pets/get/responses/200/content/*~1*');
    expect(d.fix, contains('springdoc.default-produces-media-type'));
  });

  test('component-key-characters; aspnet gets CustomSchemaIds', () {
    final run = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    "Page[User]": {type: object}
    Ns.Outer+Inner: {type: object}
    Pet_v2.1-beta: {type: object}
  responses:
    "Not Found": {description: missing}
''', preset: Preset.aspnet);
    final d = run.of(DiagnosticCode.invalidComponentKey);
    expect(d.map((d) => d.pointer?.value), [
      '#/components/schemas/Page[User]',
      '#/components/schemas/Ns.Outer+Inner',
      '#/components/responses/Not Found',
    ]);
    expect(d.first.fix, contains('CustomSchemaIds'));
  });

  test('discriminator-property-required: the holder requires the property', () {
    final d = NormalizerFixture(r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      discriminator: {propertyName: kind}
      required: [kind]
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/Dog'}
    Cat: {type: object}
    Dog: {type: object}
''').of(DiagnosticCode.discriminatorNotRequired);
    expect(d, isEmpty);
  });

  test('discriminator-mapping-target: a dotted name that is a schema', () {
    final d = NormalizerFixture(r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      discriminator:
        propertyName: kind
        mapping:
          cat: Ns.Cat
          dog: Ns.Missing
      oneOf:
        - {$ref: '#/components/schemas/Ns.Cat'}
    Ns.Cat: {type: object, required: [kind]}
''').of(DiagnosticCode.discriminatorMappingUnresolved);
    expect(d.map((d) => d.pointer?.value), [
      '#/components/schemas/Pet/discriminator/mapping/dog',
    ]);
    expect(
      d.single.message,
      'discriminator.mapping "dog" points to "Ns.Missing", which does not '
      'exist.',
    );
  });

  test('discriminator-mapping-target: a remote reference is not read', () {
    final d = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      discriminator:
        propertyName: kind
        mapping:
          cat: 'https://example.com/pets.yaml#/Cat'
      oneOf:
        - {type: object, required: [kind]}
''').of(DiagnosticCode.discriminatorMappingUnresolved);
    expect(
      d.single.message,
      'discriminator.mapping "cat" points to '
      '"https://example.com/pets.yaml#/Cat", a remote document; remote '
      'references are not read.',
    );
  });
}
