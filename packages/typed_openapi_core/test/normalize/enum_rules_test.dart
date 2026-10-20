import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/model/schema.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  String spec(String schemas) =>
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\n'
      'components:\n  schemas:\n$schemas';

  group('dedupe-enum-values', () {
    test('repeats are removed, the first occurrence stays, case is kept', () {
      final run = NormalizerFixture(
        spec('''
    Role: {type: string, enum: [user, admin, user, Admin, admin]}
    Level: {type: integer, enum: [1, 2.0, 2]}
'''),
      );
      final schemas = run.result.model.document.components!.schemas;
      expect((schemas['Role']! as SchemaObject).enumValues, [
        'user',
        'admin',
        'Admin',
      ]);
      expect((schemas['Level']! as SchemaObject).enumValues, [1, 2.0]);
      final d = run.of(DiagnosticCode.duplicateEnumValue);
      expect(d.map((d) => d.pointer?.value), [
        '#/components/schemas/Role/enum',
        '#/components/schemas/Level/enum',
      ]);
      expect(
        d.first.message,
        'The enum repeats "user", "admin"; the repeats are removed and the '
        'first occurrence of each value is kept.',
      );
    });

    test('a repeated non-finite number is described, not thrown on', () {
      final run = NormalizerFixture(
        spec('''
    Limit: {type: number, enum: [.inf, .inf, 1, [-.inf], [-.inf]]}
'''),
      );
      final d = run.of(DiagnosticCode.duplicateEnumValue).single;
      expect(d.message, contains('The enum repeats .inf, [-.inf];'));
      final schemas = run.result.model.document.components!.schemas;
      expect((schemas['Limit']! as SchemaObject).enumValues, [
        double.infinity,
        1,
        [double.negativeInfinity],
      ]);
    });

    test('many repeats suggest merged enums; nestjs gets enumName', () {
      final run = NormalizerFixture(
        spec('''
    Status:
      type: string
      enum: [BUILT, ERROR, QUEUED, READY, BUILT, ERROR, QUEUED, READY]
'''),
        preset: .nestjs,
      );
      final d = run.of(DiagnosticCode.duplicateEnumValue).single;
      expect(d.message, contains('several enums merged into one'));
      expect(d.fix, contains('enumName'));
    });
  });

  group('nullable-enum-one-of', () {
    test('oneOf of a null-only enum and a reference is reported', () {
      final run = NormalizerFixture(
        spec(r'''
    Currency: {type: string, enum: [EUR, USD]}
    Price:
      type: object
      properties:
        currency:
          nullable: true
          oneOf:
            - {type: string, nullable: true, enum: [null]}
            - {$ref: '#/components/schemas/Currency'}
'''),
      );
      final d = run.of(DiagnosticCode.nullableEnumOneOf).single;
      expect(
        d.pointer?.value,
        '#/components/schemas/Price/properties/currency/oneOf',
      );
      expect(d.message, contains('"#/components/schemas/Currency"'));
    });

    test('nestjs is told how 12 spells the null, not to stay on 3.0', () {
      final run = NormalizerFixture(
        spec(r'''
    Currency: {type: string, enum: [EUR, USD]}
    Price:
      type: object
      properties:
        currency:
          nullable: true
          oneOf:
            - {type: string, nullable: true, enum: [null]}
            - {$ref: '#/components/schemas/Currency'}
'''),
        preset: .nestjs,
      );
      final fix = run.of(DiagnosticCode.nullableEnumOneOf).single.fix;
      expect(fix, contains("enumName: 'Currency', nullable: true"));
      expect(fix, contains('@nestjs/swagger 12'));
      expect(fix, isNot(contains('keep the document at OpenAPI 3.0')));
    });

    test('an ordinary oneOf is not reported', () {
      final run = NormalizerFixture(
        spec(r'''
    Pet:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {type: string, enum: [none]}
    Cat: {type: object}
'''),
      );
      expect(run.of(DiagnosticCode.nullableEnumOneOf), isEmpty);
    });
  });
}
