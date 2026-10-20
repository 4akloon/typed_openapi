import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapped_ir.dart';
import '../helpers/mapping.dart';

void main() {
  group('lossy names (TOA559)', () {
    test('reports a type, a field and an enum value that lost letters', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Größe:
      type: object
      properties:
        größe: {type: string}
        size: {type: string, enum: [Größe, small]}
''');
      final (ir, types) = mapComponents(fixture, ['Größe']);
      expect(types, {'Größe': 'GrE'});
      expect(fieldsOf(ir, 'GrE'), [
        'grE(größe): String?',
        'size(size): GrESize?',
      ]);
      expect(MappedIr.valuesOf(ir, 'GrESize'), ['grE=Größe', 'small=small']);
      expect(fixture.codes, [
        (DiagnosticCode.nameLossy, '#/components/schemas/Größe'),
        (
          DiagnosticCode.nameLossy,
          '#/components/schemas/Größe/properties/größe',
        ),
        (
          DiagnosticCode.nameLossy,
          '#/components/schemas/Größe/properties/size',
        ),
      ]);
      expect(
        fixture.reported[0].message,
        'Schema "Größe" lost characters when it became the Dart name "GrE": '
        'letters outside ASCII are dropped.',
      );
      expect(fixture.reported[0].fix, '''
Name it explicitly to keep the meaning. Override:
schemas:
  "Größe":
    name: GrE''');
      expect(fixture.reported[1].fix, '''
Name it explicitly to keep the meaning. Override:
schemas:
  "Größe":
    properties:
      "größe":
        name: grE''');
      // The only fix of an enum value is at the source.
      expect(fixture.reported[2].fix, contains('x-enum-varnames'));
    });

    test('is silent for changes of case and separators', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    my_thing:
      type: object
      properties:
        X-Request-ID: {type: string}
        user_name: {type: string, enum: [in-progress, Done]}
''');
      final (ir, types) = mapComponents(fixture, ['my_thing']);
      expect(types, {'my_thing': 'MyThing'});
      expect(fieldsOf(ir, 'MyThing'), [
        'xRequestID(X-Request-ID): String?',
        'userName(user_name): MyThingUserName?',
      ]);
      expect(fixture.reported, isEmpty);
    });

    test('an override name silences it', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Größe:
      type: object
      properties:
        größe: {type: string}
''',
        overrides: '''
schemas:
  Größe:
    name: Groesse
    properties:
      größe: {name: groesse}
''',
      );
      final (ir, types) = mapComponents(fixture, ['Größe']);
      expect(types, {'Größe': 'Groesse'});
      expect(fieldsOf(ir, 'Groesse'), ['groesse(größe): String?']);
      expect(fixture.reported, isEmpty);
    });
  });

  group('override names (TOA560)', () {
    test('are validated and the name made from them is used (I8)', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        a: {type: string}
        b: {type: string}
        c: {type: string}
        d: {type: string}
    Cat: {type: object, properties: {a: {type: string}}}
    Dog: {type: object, properties: {a: {type: string}}}
    Eel: {type: object, properties: {a: {type: string}}}
''',
        overrides: '''
schemas:
  Pet:
    name: my thing
    properties:
      a: {name: my field}
      b: {name: _private}
      c: {name: 1x}
      d: {name: Upper}
  Cat: {name: _hidden}
  Dog: {name: "日本"}
  Eel: {name: Fine}
''',
      );
      final (ir, types) = mapComponents(fixture, ['Pet', 'Cat', 'Dog', 'Eel']);
      expect(types, {
        'Pet': 'MyThing',
        'Cat': 'Hidden',
        'Dog': 'Dog',
        'Eel': 'Fine',
      });
      expect(fieldsOf(ir, 'MyThing'), [
        'myField(a): String?',
        'private(b): String?',
        r'$1X(c): String?',
        'upper(d): String?',
      ]);
      expect(
        [
          for (final d in fixture.reported) (d.code, d.file, d.pointer?.value),
        ],
        [
          (DiagnosticCode.overrideNameInvalid, 'o.yaml', '#/schemas/Pet/name'),
          (DiagnosticCode.overrideNameInvalid, 'o.yaml', '#/schemas/Cat/name'),
          (DiagnosticCode.overrideNameInvalid, 'o.yaml', '#/schemas/Dog/name'),
          (
            DiagnosticCode.overrideNameInvalid,
            'o.yaml',
            '#/schemas/Pet/properties/a/name',
          ),
          (
            DiagnosticCode.overrideNameInvalid,
            'o.yaml',
            '#/schemas/Pet/properties/b/name',
          ),
          (
            DiagnosticCode.overrideNameInvalid,
            'o.yaml',
            '#/schemas/Pet/properties/c/name',
          ),
          (
            DiagnosticCode.overrideNameInvalid,
            'o.yaml',
            '#/schemas/Pet/properties/d/name',
          ),
        ],
      );
      expect(
        fixture.reported.first.message,
        'The name "my thing" of this override is not a valid Dart type name; '
        '"MyThing" is used.',
      );
      expect(
        fixture.reported[2].message,
        'The name "日本" of this override is not a valid Dart type name and '
        'has no ASCII letter or digit; the override is ignored.',
      );
      expect(fixture.reported.first.span, isNotNull);
    });

    test('valid names give no diagnostic', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {a: {type: string}}}
''',
        overrides: '''
schemas:
  Pet:
    name: Animal
    properties:
      a: {name: nick_name}
''',
      );
      final (ir, _) = mapComponents(fixture, ['Pet']);
      expect(fieldsOf(ir, 'Animal'), ['nick_name(a): String?']);
      expect(fixture.reported, isEmpty);
    });
  });

  group('the override a name report suggests (I4)', () {
    test('an inline type is not offered a name override', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        info: {type: object, properties: {a: {type: string}}}
    OrderInfo: {type: object, properties: {b: {type: string}}}
''');
      final (ir, types) = mapComponents(fixture, ['Order', 'OrderInfo']);
      expect(types, {'Order': 'Order', 'OrderInfo': 'OrderInfo'});
      expect(fieldsOf(ir, 'Order'), ['info(info): OrderInfo2?']);
      expect(fixture.codes, [
        (
          DiagnosticCode.nameCollision,
          '#/components/schemas/Order/properties/info',
        ),
      ]);
      expect(fixture.reported.single.fix, isNot(contains('Override')));
      expect(fixture.reported.single.fix, contains('components.schemas'));
    });

    test('a component is, and the override renames its type', () {
      const text = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        info: {$ref: '#/components/schemas/Info'}
    List: {type: object, properties: {a: {type: string}}}
    Info: {type: object, properties: {b: {type: string}}}
''';
      final first = IrFixture(text);
      mapComponents(first, ['List']);
      expect(first.reported.single.fix, '''
Name the type explicitly to keep the name stable. Override:
schemas:
  List:
    name: ListModel''');
      final second = IrFixture(
        text,
        overrides: '''
schemas:
  List: {name: ListModel}
''',
      );
      final (_, types) = mapComponents(second, ['List']);
      expect(types, {'List': 'ListModel'});
      expect(second.reported, isEmpty);
    });

    test('a request model is not offered one', () {
      final fixture = IrFixture(
        r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get: {responses: {'200': {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}}
    post:
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {'200': {description: ok}}
  /others:
    get: {responses: {'200': {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Zed'}}}}}}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: integer, readOnly: true}, name: {type: string}}}
    Zed: {type: object, properties: {a: {type: string}}}
''',
        overrides: '''
schemas:
  Zed: {name: PetInput}
''',
      );
      final ir = IrBuilder(fixture.diagnostics).build(
        fixture.context.spec,
        fixture.context.client,
      );
      expect(ir.declarations.map((d) => d.name), [
        'Pet',
        'PetInput',
        'PetInput2',
      ]);
      final report = fixture.reported.singleWhere(
        (d) => d.code == DiagnosticCode.nameCollision,
      );
      expect(report.pointer?.value, '#/components/schemas/Pet');
      expect(report.message, contains('"PetInput2"'));
      expect(report.fix, isNot(contains('Override')));
    });
  });

  test('names that the runtime exports are reserved', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    QueryStyle: {type: object, properties: {a: {type: string}}}
    PathStyle: {type: object, properties: {a: {type: string}}}
''');
    final (_, types) = mapComponents(fixture, ['QueryStyle', 'PathStyle']);
    expect(types, {
      'QueryStyle': 'QueryStyleModel',
      'PathStyle': 'PathStyleModel',
    });
  });
}
