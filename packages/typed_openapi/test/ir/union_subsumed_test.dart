import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

UnionDecl union(ClientIr ir, String name) =>
    ir.declarations.firstWhere((d) => d.name == name) as UnionDecl;

void main() {
  const head = '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Customer: {type: object, properties: {id: {type: string}}}
''';

  for (final kind in ['anyOf', 'oneOf']) {
    test('a $kind of a string and its enum is String (TOA455)', () {
      final fixture = IrFixture('''
$head    Unset:
      $kind: [{type: string}, {type: string, enum: ['']}]
    Holder:
      type: object
      properties:
        coupon:
          $kind:
            - {type: string}
            - {enum: ['']}
''');
      final (ir, types) = mapComponents(fixture, ['Unset', 'Holder']);
      expect(types['Unset'], 'String');
      expect(fieldsOf(ir, 'Holder'), ['coupon(coupon): String?']);
      expect(ir.declarations.map((d) => d.name), ['Holder']);
      expect(fixture.codes, [
        (
          DiagnosticCode.unionBranchSubsumed,
          '#/components/schemas/Unset/$kind/1',
        ),
        (
          DiagnosticCode.unionBranchSubsumed,
          '#/components/schemas/Holder/properties/coupon/$kind/1',
        ),
      ]);
      final report = fixture.reported.first;
      expect(report.severity.name, 'info');
      expect(
        report.message,
        "The enum [''] branch adds no value to the string branch; the schema "
        'is generated as the string branch alone.',
      );
    });
  }

  test('an integer enum next to an integer, or a number, is subsumed', () {
    final fixture = IrFixture('''
$head    Zero:
      anyOf: [{type: integer}, {type: integer, enum: [0]}]
    Rate:
      anyOf: [{type: number}, {type: integer, enum: [1, 2]}]
    Flag:
      anyOf: [{type: boolean}, {const: true}]
''');
    final (_, types) = mapComponents(fixture, ['Zero', 'Rate', 'Flag']);
    expect(types, {'Zero': 'int', 'Rate': 'num', 'Flag': 'bool'});
    expect(fixture.codes.map((c) => c.$1).toSet(), {
      DiagnosticCode.unionBranchSubsumed,
    });
    expect(fixture.codes, hasLength(3));
  });

  test('a branch that is not plain keeps the union as it was', () {
    final fixture = IrFixture('''
$head    Dated:
      anyOf: [{type: string, format: date-time}, {enum: ['']}]
    Short:
      anyOf: [{type: string, minLength: 1}, {enum: ['']}]
    Pattern:
      anyOf: [{type: string, pattern: '^a'}, {enum: [a]}]
    Id:
      anyOf: [{type: string}, {type: integer, enum: [1]}]
    Rate:
      anyOf: [{type: integer}, {type: number, enum: [1.5]}]
''');
    final (ir, types) = mapComponents(fixture, [
      'Dated',
      'Short',
      'Pattern',
      'Id',
      'Rate',
    ]);
    expect(types['Dated'], 'JsonValue');
    expect(types['Short'], 'JsonValue');
    expect(types['Pattern'], 'JsonValue');
    expect(fixture.codes, [
      (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Dated'),
      (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Short'),
      (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Pattern'),
    ]);
    expect(union(ir, 'Id').dispatch, UnionDispatch.jsonType);
    expect(union(ir, 'Id').variants.map((v) => v.name), [
      'IdString',
      'IdVariant2Case',
    ]);
    expect(union(ir, 'Rate').variants.map((v) => v.name), [
      'RateInt',
      'RateVariant2Case',
    ]);
  });

  test('the enum branch beside a model is dropped, the rest dispatches', () {
    final fixture = IrFixture('''
$head    Owner:
      anyOf:
        - {type: string}
        - {type: string, enum: ['']}
        - \$ref: '#/components/schemas/Customer'
''');
    final (ir, _) = mapComponents(fixture, ['Owner']);
    final owner = union(ir, 'Owner');
    expect(owner.dispatch, UnionDispatch.jsonType);
    expect(owner.variants.map((v) => v.name), ['OwnerString', 'OwnerCustomer']);
    expect(fixture.codes, [
      (
        DiagnosticCode.unionBranchSubsumed,
        '#/components/schemas/Owner/anyOf/1',
      ),
    ]);
    expect(
      fixture.reported.single.message,
      "The enum [''] branch adds no value to the string branch; it is "
      'dropped from the union.',
    );
  });

  test('a null branch keeps the collapsed type nullable', () {
    final fixture = IrFixture('''
$head    Maybe:
      anyOf: [{type: string}, {enum: ['']}, {type: 'null'}]
''');
    final (_, types) = mapComponents(fixture, ['Maybe']);
    expect(types['Maybe'], 'String?');
    expect(fixture.codes, [
      (
        DiagnosticCode.unionBranchSubsumed,
        '#/components/schemas/Maybe/anyOf/1',
      ),
    ]);
  });

  test('a constraint that every enum value satisfies still subsumes it', () {
    final fixture = IrFixture('''
$head    Name:
      anyOf: [{type: string, maxLength: 5000}, {type: string, enum: ['']}]
    Pin:
      anyOf: [{type: string, minLength: 0, maxLength: 4}, {const: abc}]
    Level:
      anyOf:
        - {type: integer, minimum: 0, maximum: 10, multipleOf: 5}
        - {type: integer, enum: [0, 5, 10]}
    Open:
      anyOf:
        - {type: integer, minimum: 0, exclusiveMinimum: true}
        - {type: integer, enum: [1]}
    Fine:
      anyOf:
        - {type: number, exclusiveMaximum: 2.5}
        - {type: integer, enum: [1, 2]}
''');
    final (_, types) = mapComponents(fixture, [
      'Name',
      'Pin',
      'Level',
      'Open',
      'Fine',
    ]);
    expect(types, {
      'Name': 'String',
      'Pin': 'String',
      'Level': 'int',
      'Open': 'int',
      'Fine': 'num',
    });
    expect(fixture.codes, hasLength(5));
  });

  test('an enum value that breaks a constraint keeps the union', () {
    final fixture = IrFixture('''
$head    Name:
      anyOf: [{type: string, maxLength: 3}, {enum: ['', abcd]}]
    Level:
      anyOf:
        - {type: integer, minimum: 1}
        - {type: integer, enum: [0, 1]}
    Open:
      anyOf:
        - {type: integer, minimum: 1, exclusiveMinimum: true}
        - {type: integer, enum: [1]}
    Step:
      anyOf: [{type: integer, multipleOf: 5}, {type: integer, enum: [5, 7]}]
''');
    final (_, types) = mapComponents(fixture, [
      'Name',
      'Level',
      'Open',
      'Step',
    ]);
    expect(types, {
      'Name': 'JsonValue',
      'Level': 'JsonValue',
      'Open': 'JsonValue',
      'Step': 'JsonValue',
    });
    expect(
      fixture.codes.where((c) => c.$1 == DiagnosticCode.unionBranchSubsumed),
      isEmpty,
    );
  });

  test('a reference to a plain scalar is the plain branch', () {
    final fixture = IrFixture('''
$head    Slug: {type: string, maxLength: 20}
    Count: {type: integer}
    Code: {type: string, format: uuid}
    Tag: {type: string, enum: [a]}
    Short: {type: string, maxLength: 1}
    Name:
      anyOf: [\$ref: '#/components/schemas/Slug', {enum: ['']}]
    Number:
      oneOf: [\$ref: '#/components/schemas/Count', {const: 3}]
    Formatted:
      anyOf: [\$ref: '#/components/schemas/Code', {enum: ['']}]
    Listed:
      anyOf: [\$ref: '#/components/schemas/Tag', {enum: ['']}]
    Tight:
      anyOf: [\$ref: '#/components/schemas/Short', {enum: [ab]}]
''');
    final (_, types) = mapComponents(fixture, [
      'Name',
      'Number',
      'Formatted',
      'Listed',
      'Tight',
    ]);
    expect(types['Name'], 'String');
    expect(types['Number'], 'int');
    expect(types['Formatted'], 'JsonValue');
    expect(types['Listed'], isNot('String'));
    expect(types['Tight'], 'JsonValue');
    expect(
      [
        for (final c in fixture.codes)
          if (c.$1 == DiagnosticCode.unionBranchSubsumed) c.$2,
      ],
      [
        '#/components/schemas/Name/anyOf/1',
        '#/components/schemas/Number/oneOf/1',
      ],
    );
  });

  test('a field keeps the values of the branch it drops', () {
    final fixture = IrFixture('''
$head    Transcription:
      type: object
      properties:
        model:
          description: The model.
          anyOf:
            - {type: string}
            - {type: string, enum: [whisper-1, 'gpt`4', '']}
        plain: {type: string}
        three:
          anyOf:
            - {type: string}
            - {enum: [x]}
            - \$ref: '#/components/schemas/Customer'
''');
    final (ir, _) = mapComponents(fixture, ['Transcription']);
    final fields =
        (ir.declarations.firstWhere((d) => d.name == 'Transcription')
                as ModelDecl)
            .fields;
    expect(
      {for (final f in fields) f.name: f.knownValues},
      {
        'model': ['whisper-1', 'gpt`4', ''],
        'plain': <Object?>[],
        'three': ['x'],
      },
    );
  });

  test('valid unions and enums report no TOA455', () {
    final fixture = IrFixture('''
$head    Color:
      anyOf: [{const: red}, {const: green}]
    Mixed:
      oneOf: [{type: string}, {type: integer}, {type: boolean}]
    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Customer'
        - {type: object, properties: {kind: {const: fish}}}
      discriminator: {propertyName: kind}
''');
    mapComponents(fixture, ['Color', 'Mixed', 'Pet']);
    expect(
      fixture.codes.where((c) => c.$1 == DiagnosticCode.unionBranchSubsumed),
      isEmpty,
    );
  });
}
