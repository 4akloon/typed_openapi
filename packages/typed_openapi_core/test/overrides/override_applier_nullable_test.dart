import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/override_run.dart';

const _header30 = OverrideRun.header30;
const _header31 = OverrideRun.header31;

void main() {
  test('nullable is "null" in type from 3.1; type keeps nullability', () {
    final run = OverrideRun(
      '''
$_header31
components:
  schemas:
    A: {type: string}
    B: {type: [integer, 'null']}
    C: {type: [string, 'null']}
    D: {properties: {x: {type: string}}}
''',
      '''
schemas:
  A: {nullable: true}
  B: {type: number}
  C: {nullable: false}
  D: {nullable: true}
''',
    );
    expect(run.at('#/components/schemas/A/type'), ['string', 'null']);
    expect(run.at('#/components/schemas/B/type'), ['number', 'null']);
    expect(run.at('#/components/schemas/C/type'), 'string');
    expect(run.at('#/components/schemas/D'), {
      'properties': {
        'x': {'type': 'string'},
      },
    });
    expect(run.overrideDiagnostics, [
      (DiagnosticCode.invalidOverride, '#/schemas/D/nullable'),
    ]);
  });

  test(
    '"type: null" on a nullable 3.1 schema removes the type and says so',
    () {
      final run = OverrideRun(
        '''
$_header31
components:
  schemas:
    A: {type: [string, 'null'], description: d}
''',
        'schemas: {A: {type: null}}\n',
      );
      expect(run.overrideDiagnostics, [
        (DiagnosticCode.overrideNullabilityDropped, '#/schemas/A/type'),
      ]);
      expect(run.at('#/components/schemas/A'), {'description': 'd'});
    },
  );

  test('a 3.1 nullable reference is already nullable', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner:
          anyOf:
            - {$ref: '#/components/schemas/Owner'}
            - {type: 'null'}
''';
    final same = OverrideRun(
      '$_header31$spec',
      'schemas: {Pet: {properties: {owner: {nullable: true}}}}\n',
    );
    expect(same.overrideDiagnostics, [
      (
        DiagnosticCode.overrideUnchanged,
        '#/schemas/Pet/properties/owner/nullable',
      ),
    ]);
    final off = OverrideRun(
      '$_header31$spec',
      'schemas: {Pet: {properties: {owner: {nullable: false}}}}\n',
    );
    expect(off.overrideDiagnostics, isEmpty);
    expect(off.at('#/components/schemas/Pet/properties/owner'), {
      r'$ref': '#/components/schemas/Owner',
    });
  });

  group('3.1 nullable through a "null" branch', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner:
          anyOf: [{$ref: '#/components/schemas/Owner'}, {type: 'null'}]
          default: null
          title: Owner
        age:
          anyOf: [{type: integer}, {type: 'null'}]
          default: null
          title: Age
        nick:
          oneOf: [{type: string}, {type: 'null'}]
          description: d
        plain: {description: x}
''';

    test('"nullable: true" says the schema is already nullable', () {
      final run = OverrideRun('$_header31$spec', '''
schemas:
  Pet:
    properties:
      owner: {nullable: true}
      age: {nullable: true}
      nick: {nullable: true}
''');
      expect(run.overrideDiagnostics, [
        for (final name in ['owner', 'age', 'nick'])
          (
            DiagnosticCode.overrideUnchanged,
            '#/schemas/Pet/properties/$name/nullable',
          ),
      ]);
    });

    test('"nullable: false" keeps the branch and the siblings', () {
      final run = OverrideRun('$_header31$spec', '''
schemas:
  Pet:
    properties:
      owner: {nullable: false}
      age: {nullable: false}
      nick: {nullable: false}
      plain: {nullable: false}
''');
      expect(run.overrideDiagnostics, [
        (
          DiagnosticCode.overrideUnchanged,
          '#/schemas/Pet/properties/plain/nullable',
        ),
      ]);
      const props = '#/components/schemas/Pet/properties';
      expect(run.at('$props/owner'), {
        r'$ref': '#/components/schemas/Owner',
        'title': 'Owner',
      });
      expect(run.at('$props/age'), {'type': 'integer', 'title': 'Age'});
      expect(run.at('$props/nick'), {'type': 'string', 'description': 'd'});
    });

    test('a field that comes with "nullable" is not set beside the union', () {
      final run = OverrideRun('$_header31$spec', '''
schemas:
  Pet:
    properties:
      age: {nullable: false, enum: [1]}
''');
      expect(run.overrideDiagnostics, [
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/properties/age/enum'),
      ]);
    });
  });

  group(r'a "$ref" with siblings and a "nullable" override', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          $ref: '#/components/schemas/Owner'
          description: buddy
          readOnly: true
''';
    const nullable = '''
schemas: {Pet: {properties: {friend: {nullable: true}}}}
''';
    const friend = '#/components/schemas/Pet/properties/friend';

    test('keeps the siblings in 3.1', () {
      final run = OverrideRun('$_header31$spec', nullable);
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {
        'description': 'buddy',
        'readOnly': true,
        'anyOf': [
          {r'$ref': '#/components/schemas/Owner'},
          {'type': 'null'},
        ],
      });
    });

    test('keeps the siblings in 3.0', () {
      final run = OverrideRun('$_header30$spec', nullable);
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {
        'description': 'buddy',
        'readOnly': true,
        'allOf': [
          {r'$ref': '#/components/schemas/Owner'},
        ],
        'nullable': true,
      });
    });

    test('"nullable: false" on a plain reference changes nothing', () {
      for (final header in [_header30, _header31]) {
        final run = OverrideRun(
          '$header$spec',
          'schemas: {Pet: {properties: {friend: {nullable: false}}}}\n',
        );
        expect(run.overrideDiagnostics, [
          (
            DiagnosticCode.overrideUnchanged,
            '#/schemas/Pet/properties/friend/nullable',
          ),
        ]);
        expect(run.at(friend), {
          r'$ref': '#/components/schemas/Owner',
          'description': 'buddy',
          'readOnly': true,
        });
      }
    });

    test(r'an explicit "$ref" replaces the whole node', () {
      final run = OverrideRun('$_header31$spec', r'''
schemas: {Pet: {properties: {friend: {$ref: '#/components/schemas/Pet'}}}}
''');
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {r'$ref': '#/components/schemas/Pet'});
    });

    test('the 3.0 nullable form with siblings is already nullable', () {
      final run = OverrideRun(
        '''
$_header30
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          allOf: [{\$ref: '#/components/schemas/Owner'}]
          nullable: true
          description: buddy
''',
        '''
schemas: {Pet: {properties: {friend: {nullable: true}}}}
''',
      );
      expect(run.overrideDiagnostics, [
        (
          DiagnosticCode.overrideUnchanged,
          '#/schemas/Pet/properties/friend/nullable',
        ),
      ]);
      final off = OverrideRun(
        '''
$_header30
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          allOf: [{\$ref: '#/components/schemas/Owner'}]
          nullable: true
          description: buddy
''',
        '''
schemas: {Pet: {properties: {friend: {nullable: false}}}}
''',
      );
      expect(off.overrideDiagnostics, isEmpty);
      expect(off.at(friend), {
        r'$ref': '#/components/schemas/Owner',
        'description': 'buddy',
      });
    });
  });

  group('3.1 nullable union with several branches or a described null', () {
    const spec = '''
components:
  schemas:
    Pet:
      type: object
      properties:
        id:
          anyOf: [{type: integer}, {type: string}, {type: 'null'}]
          default: null
          title: Id
        tag:
          oneOf:
            - {type: string}
            - {type: 'null', description: no tag}
          description: t
        two:
          anyOf: [{type: integer}, {type: string}]
''';
    const props = '#/components/schemas/Pet/properties';

    test('"nullable: true" says it is already nullable', () {
      final run = OverrideRun('$_header31$spec', '''
schemas:
  Pet:
    properties:
      id: {nullable: true}
      tag: {nullable: true}
''');
      expect(run.overrideDiagnostics, [
        for (final name in ['id', 'tag'])
          (
            DiagnosticCode.overrideUnchanged,
            '#/schemas/Pet/properties/$name/nullable',
          ),
      ]);
    });

    test('"nullable: false" removes only the null branch', () {
      final run = OverrideRun('$_header31$spec', '''
schemas:
  Pet:
    properties:
      id: {nullable: false}
      tag: {nullable: false}
      two: {nullable: false}
''');
      expect(run.overrideDiagnostics, [
        (
          DiagnosticCode.overrideUnchanged,
          '#/schemas/Pet/properties/two/nullable',
        ),
      ]);
      expect(run.at('$props/id'), {
        'anyOf': [
          {'type': 'integer'},
          {'type': 'string'},
        ],
        'title': 'Id',
      });
      expect(run.at('$props/tag'), {'type': 'string', 'description': 't'});
    });
  });
}
