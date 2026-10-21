import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapped_ir.dart';
import '../helpers/mapping.dart';

void main() {
  group('enum value names', () {
    test('a string that is a number is named like a number (I5)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    S: {type: string, enum: ["-1", "0.5", "2", "1e3", "-0.25", "1st"]}
''');
      final (ir, _) = mapComponents(fixture, ['S']);
      expect(MappedIr.valuesOf(ir, 'S'), [
        'valueMinus1=-1',
        'value0_5=0.5',
        'value2=2',
        'value1e3=1e3',
        'valueMinus0_25=-0.25',
        r'$1St=1st',
      ]);
      expect(fixture.reported, isEmpty);
    });

    test('a number in exponent form gives a valid name (I6)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    N: {type: number, enum: [0.0000001, 1e21, -2.5e-8]}
''');
      final (ir, _) = mapComponents(fixture, ['N']);
      expect(
        [for (final v in (ir.declarations.single as EnumDecl).values) v.name],
        ['value1eMinus7', 'value1e21', 'valueMinus2_5eMinus8'],
      );
      expect(fixture.reported, isEmpty);
    });
  });

  group('x-enum-varnames and x-enum-descriptions (TOA351)', () {
    test('a null description is no description, the rest is kept', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Nulls:
      type: integer
      enum: [1, 2, 3]
      x-enum-varnames: [one, two, three]
      x-enum-descriptions: [First, null, Third]
    Bad:
      type: integer
      enum: [1, 2]
      x-enum-descriptions: [First, 2]
''');
      final (ir, _) = mapComponents(fixture, ['Nulls', 'Bad']);
      expect(
        [
          for (final v
              in (ir.declarations.firstWhere((d) => d.name == 'Nulls')
                      as EnumDecl)
                  .values)
            v.description,
        ],
        ['First', null, 'Third'],
      );
      expect(fixture.codes, [
        (
          DiagnosticCode.enumVarnamesInvalid,
          '#/components/schemas/Bad/x-enum-descriptions',
        ),
      ]);
    });

    test('reports a list that is not strings of the enum length (I7)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Short: {type: integer, enum: [1, 2], x-enum-varnames: [one]}
    Mixed: {type: integer, enum: [1, 2], x-enum-varnames: [one, 2]}
    Text: {type: integer, enum: [1, 2], x-enum-varnames: nope}
    Described:
      type: integer
      enum: [1, 2]
      x-enum-varnames: [one, two]
      x-enum-descriptions: [First]
    Fine:
      type: integer
      enum: [1, 2]
      x-enum-varnames: [one, two]
      x-enum-descriptions: [First, Second]
''');
      final (ir, _) = mapComponents(fixture, [
        'Short',
        'Mixed',
        'Text',
        'Described',
        'Fine',
      ]);
      expect(MappedIr.valuesOf(ir, 'Short'), ['value1=1', 'value2=2']);
      expect(MappedIr.valuesOf(ir, 'Described'), ['one=1', 'two=2']);
      expect(MappedIr.valuesOf(ir, 'Fine'), ['one=1', 'two=2']);
      expect(fixture.codes, [
        (
          DiagnosticCode.enumVarnamesInvalid,
          '#/components/schemas/Short/x-enum-varnames',
        ),
        (
          DiagnosticCode.enumVarnamesInvalid,
          '#/components/schemas/Mixed/x-enum-varnames',
        ),
        (
          DiagnosticCode.enumVarnamesInvalid,
          '#/components/schemas/Text/x-enum-varnames',
        ),
        (
          DiagnosticCode.enumVarnamesInvalid,
          '#/components/schemas/Described/x-enum-descriptions',
        ),
      ]);
      expect(
        fixture.reported[0].message,
        'x-enum-varnames must be a list of strings with one entry per enum '
        'value (2); it is ignored.',
      );
    });

    test('takes the names of an enum with null by the written list', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    E: {type: [string, "null"], enum: [a, b, null], x-enum-varnames: [first, second, none]}
''');
      final (ir, _) = mapComponents(fixture, ['E']);
      expect(MappedIr.valuesOf(ir, 'E'), ['first=a', 'second=b']);
      expect(fixture.reported, isEmpty);
    });

    test(
      'gives each inline enum its own declaration, varnames equal or not',
      () {
        final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        status: {type: string, enum: [a, b], x-enum-varnames: [first, second]}
        state: {type: string, enum: [a, b], x-enum-varnames: [one, two]}
        phase: {type: string, enum: [a, b], x-enum-varnames: [first, second]}
        stage: {type: string, enum: [a, b]}
''');
        final (ir, _) = mapComponents(fixture, ['Order']);
        expect(fieldsOf(ir, 'Order'), [
          'status(status): OrderStatus?',
          'state(state): OrderState?',
          'phase(phase): OrderPhase?',
          'stage(stage): OrderStage?',
        ]);
        expect(MappedIr.valuesOf(ir, 'OrderState'), ['one=a', 'two=b']);
        expect(fixture.reported, isEmpty);
      },
    );
  });

  group('enum value names (final review M5, M14)', () {
    test('a value with no ASCII letter or digit is TOA552, an info that says '
        'x-enum-varnames', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Mode: {type: string, enum: ["*/*", "@", ok]}
    Bad:
      type: string
      enum: [a, b]
      x-enum-varnames: ["$", fine]
''');
      final (ir, _) = mapComponents(fixture, ['Mode', 'Bad']);
      expect(MappedIr.valuesOf(ir, 'Mode'), [
        'value_=*/*',
        'value_2=@',
        'ok=ok',
      ]);
      expect(MappedIr.valuesOf(ir, 'Bad'), ['a=a', 'fine=b']);
      final found = fixture.reported
          .where((d) => d.code == DiagnosticCode.nameUnrepresentable)
          .toList();
      expect(found, hasLength(3));
      for (final d in found) {
        expect(d.severity, Severity.info);
        expect(d.fix, contains('x-enum-varnames'));
      }
      expect(found.first.message, contains('x-enum-varnames'));
    });

    test('unknown is reserved for the unknown value of an enum', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Mode: {type: string, enum: [known, unknown, Unknown]}
''');
      final (ir, _) = mapComponents(fixture, ['Mode']);
      expect(MappedIr.valuesOf(ir, 'Mode'), [
        'known=known',
        'unknown_=unknown',
        'unknown_2=Unknown',
      ]);
      expect(fixture.reported.map((d) => d.code), [
        DiagnosticCode.nameReserved,
        DiagnosticCode.nameReserved,
      ]);
      expect(fixture.reported.first.message, contains('"unknown_"'));
    });
  });
}
