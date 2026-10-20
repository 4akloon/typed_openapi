import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapped_ir.dart';
import '../helpers/mapping.dart';

void main() {
  group('oneOf and anyOf beside properties (T5 I1)', () {
    test('a type: object branch without properties adds only constraints', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pick:
      type: object
      properties: {a: {type: string}, b: {type: string}}
      anyOf:
        - {type: object, required: [a]}
        - {type: object, required: [b]}
    Real:
      type: object
      properties: {a: {type: string}}
      oneOf:
        - {type: object, properties: {x: {type: string}}}
        - {type: object, properties: {y: {type: string}}}
''', generation: const GenerationConfig(union: UnionMode.structural));
      final (ir, types) = mapComponents(fixture, ['Pick', 'Real']);
      expect(types['Pick'], 'Pick');
      expect(fieldsOf(ir, 'Pick'), ['a(a): String?', 'b(b): String?']);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Pick/anyOf',
        ),
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/Real/properties',
        ),
      ]);
    });

    test('branches that only add constraints leave a model (TOA255)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Contact:
      type: object
      properties: {email: {type: string}, phone: {type: string}}
      oneOf: [{required: [email]}, {required: [phone]}]
    Contact2:
      type: object
      properties: {email: {type: string}, phone: {type: string}}
      anyOf: [{required: [email]}, {required: [phone]}]
    Contact3:
      type: object
      oneOf: [{required: [email]}, {required: [phone]}]
''');
      final (ir, types) = mapComponents(fixture, [
        'Contact',
        'Contact2',
        'Contact3',
      ]);
      expect(types, {
        'Contact': 'Contact',
        'Contact2': 'Contact2',
        'Contact3': 'Map<String, JsonValue>',
      });
      expect(fieldsOf(ir, 'Contact'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fieldsOf(ir, 'Contact2'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact/oneOf',
        ),
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact2/anyOf',
        ),
      ]);
    });

    test('const branches of one type are one enum, with no diagnostic', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Color: {type: string, oneOf: [{const: red}, {const: green}]}
    Size: {type: string, anyOf: [{const: s}, {enum: [m, l]}, {type: 'null'}]}
    Holder:
      type: object
      properties:
        color: {$ref: '#/components/schemas/Color'}
        size: {$ref: '#/components/schemas/Size'}
''');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), [
        'color(color): Color?',
        'size(size): Size?',
      ]);
      expect(
        MappedIr.declaration<EnumDecl>(ir, 'Color').values.map((v) => v.value),
        [
          'red',
          'green',
        ],
      );
      expect(
        MappedIr.declaration<EnumDecl>(ir, 'Size').values.map((v) => v.value),
        [
          's',
          'm',
          'l',
        ],
      );
    });

    test('a branch that is a type keeps the union', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    Mixed: {oneOf: [{const: x}, {$ref: '#/components/schemas/A'}]}
''');
      final (ir, _) = mapComponents(fixture, ['Mixed']);
      expect(MappedIr.variantsOf(ir, 'Mixed'), ['MixedVariant1', 'A']);
      expect(fixture.reported, isEmpty);
    });

    test('properties beside a union of types are ignored with TOA256', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    U:
      properties: {kind: {type: string}}
      oneOf: [{$ref: '#/components/schemas/A'}, {$ref: '#/components/schemas/B'}]
''', generation: const GenerationConfig(union: UnionMode.structural));
      final (ir, _) = mapComponents(fixture, ['U']);
      expect(MappedIr.variantsOf(ir, 'U'), ['A', 'B']);
      expect(fixture.codes, [
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/U/properties',
        ),
      ]);
      expect(
        fixture.reported.single.message,
        'The properties of this schema are ignored: it is generated as the '
        'union of its oneOf branches.',
      );
    });

    test('the discriminator property beside a union is not ignored', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {type: {type: string}}}
    B: {type: object, properties: {type: {type: string}}}
    U:
      properties: {type: {type: string}}
      required: [type]
      oneOf: [{$ref: '#/components/schemas/A'}, {$ref: '#/components/schemas/B'}]
      discriminator: {propertyName: type}
''');
      final (ir, _) = mapComponents(fixture, ['U']);
      expect(MappedIr.variantsOf(ir, 'U'), ['A', 'B']);
      expect(fixture.reported, isEmpty);
    });

    test('constraint branches inside an allOf part are TOA255', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Contact:
      allOf:
        - type: object
          properties: {email: {type: string}, phone: {type: string}}
        - oneOf: [{required: [email]}, {required: [phone]}]
''');
      final (ir, _) = mapComponents(fixture, ['Contact']);
      expect(fieldsOf(ir, 'Contact'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact/allOf/1/oneOf',
        ),
      ]);
    });

    test('branches beside allOf parts are ignored with TOA256', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    Base: {type: object, properties: {id: {type: integer}}}
    M:
      allOf: [{$ref: '#/components/schemas/Base'}]
      oneOf: [{$ref: '#/components/schemas/A'}, {type: 'null'}]
''');
      final (ir, _) = mapComponents(fixture, ['M']);
      expect(fieldsOf(ir, 'M'), ['id(id): int?']);
      expect(fixture.codes, [
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/M/oneOf',
        ),
      ]);
    });
  });
}
