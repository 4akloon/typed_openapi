import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapped_ir.dart';
import '../helpers/mapping.dart';

void main() {
  group(r'allOf of one $ref and annotation-only parts (final review I1)', () {
    const specTail = r'''
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Color: {type: string, description: A color, enum: [red, green]}
    Choice:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
    Cat: {type: object, properties: {meow: {type: string}}}
    Dog: {type: object, properties: {bark: {type: string}}}
    Holder:
      type: object
      properties:
        pet:
          allOf: [{$ref: '#/components/schemas/Pet'}, {nullable: true}]
        color:
          allOf: [{$ref: '#/components/schemas/Color'}, {description: Mine}]
        choice:
          allOf: [{$ref: '#/components/schemas/Choice'}, {nullable: true, description: Which}]
        noted:
          allOf:
            - $ref: '#/components/schemas/Pet'
            - {description: Noted, default: {name: rex}, deprecated: true, title: T}
        plain:
          allOf: [{$ref: '#/components/schemas/Pet'}, {description: Plain}]
''';
    const head = 'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n';

    test('is a reference to the target, nullable when a part says so', () {
      final fixture = IrFixture(
        '$head$specTail',
        generation: const GenerationConfig(union: UnionMode.structural),
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), [
        'pet(pet): Pet?',
        'color(color): Color?',
        'choice(choice): Choice?',
        'noted(noted): Pet?',
        'plain(plain): Pet?',
      ]);
      expect(ir.declarations.map((d) => d.name), [
        'Cat',
        'Choice',
        'Color',
        'Dog',
        'Holder',
        'Pet',
      ]);
    });

    test('keeps the annotations of the parts for the field', () {
      final fixture = IrFixture('$head$specTail');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final fields = {
        for (final f in MappedIr.declaration<ModelDecl>(ir, 'Holder').fields)
          f.name: f,
      };
      expect(fields['color']!.description, 'Mine');
      expect(fields['choice']!.description, 'Which');
      expect(fields['pet']!.description, isNull);
      expect(fields['noted']!.description, 'Noted');
      expect(fields['noted']!.defaultValue!.$1, {'name': 'rex'});
      expect(fields['noted']!.deprecated, isTrue);
      expect(fields['plain']!.deprecated, isFalse);
    });

    test('a 3.1 type: null part makes the reference nullable', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Holder:
      type: object
      properties:
        pet: {allOf: [{$ref: '#/components/schemas/Pet'}, {type: 'null'}]}
''');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), ['pet(pet): Pet?']);
      expect(ir.declarations.map((d) => d.name), ['Holder', 'Pet']);
    });

    test('a part with structure is still merged', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Strict:
      allOf: [{$ref: '#/components/schemas/Pet'}, {required: [name]}]
''');
      final (ir, _) = mapComponents(fixture, ['Strict']);
      expect(fieldsOf(ir, 'Strict'), ['name(name): String']);
    });

    test('a request body of annotation-only parts is the target model', () {
      final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /pets:
    patch:
      operationId: patchPet
      requestBody:
        content:
          application/json:
            schema:
              allOf: [{$ref: '#/components/schemas/Pet'}, {nullable: true}]
      responses: {'204': {description: ok}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
''');
      final ir = IrBuilder(
        fixture.diagnostics,
      ).build(fixture.context.spec, fixture.context.client);
      expect(ir.declarations.map((d) => d.name), ['Pet']);
      expect(fixture.reported.map((d) => d.code), [
        DiagnosticCode.operationUntagged,
      ]);
    });
  });

  group(r'annotations beside a $ref (final review I2)', () {
    const specTail = r'''
components:
  schemas:
    Status: {type: string, description: Status of anything, enum: [on, off]}
    Old: {type: string, deprecated: true, default: x}
    Holder:
      type: object
      properties:
        status:
          $ref: '#/components/schemas/Status'
          description: The pet status
          default: 'on'
          deprecated: true
        inherited: {$ref: '#/components/schemas/Status'}
        old: {$ref: '#/components/schemas/Old', default: y}
''';

    test('3.1 takes description, default and deprecated of the property', () {
      final fixture = IrFixture(
        'openapi: 3.1.0\ninfo: {title: t, version: "1"}\n$specTail',
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final fields = {
        for (final f in MappedIr.declaration<ModelDecl>(ir, 'Holder').fields)
          f.name: f,
      };
      expect(fields['status']!.description, 'The pet status');
      expect(fields['status']!.defaultValue, ('on',));
      expect(fields['status']!.deprecated, isTrue);
      // Without siblings the target's keywords are used.
      expect(fields['inherited']!.description, 'Status of anything');
      expect(fields['inherited']!.deprecated, isFalse);
      expect(fields['old']!.defaultValue, ('y',));
      expect(fields['old']!.deprecated, isTrue);
    });

    test(r'3.0 has no siblings of a $ref: the target is used', () {
      final fixture = IrFixture(
        'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n$specTail',
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final status = MappedIr.declaration<ModelDecl>(
        ir,
        'Holder',
      ).fields.firstWhere((f) => f.name == 'status');
      expect(status.description, 'Status of anything');
      expect(status.defaultValue, isNull);
      expect(status.deprecated, isFalse);
    });
  });
}
