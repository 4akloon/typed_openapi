import 'package:test/test.dart';
import 'package:typed_openapi_core/src/check/spec_checker.dart';
import 'package:typed_openapi_core/src/config/config_loader.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/display_paths.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

const _dollarRef = r'$ref';
const _brokenRef = r"{$ref: '#/components/schemas/'}";

String _spec({
  String links = '',
  String components = '',
  String extraPaths = '',
}) =>
    '''
openapi: 3.0.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses: {'204': {description: ok}}
  /links:
    get:
      operationId: listLinks
      tags: [links]
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: ${links.isEmpty ? _brokenRef : links}
$extraPaths
components:
  schemas:
    Unused: {type: object}
$components
''';

/// Checks the clients of [config] (the `clients:` body) over [spec].
({List<ClientCheck> checks, DiagnosticBag bag, TempDir dir}) _run(
  String spec,
  String clients, {
  Map<String, String> files = const {},
  Map<String, String> overrides = const {},
}) {
  final dir = TempDir();
  dir.write('api.yaml', spec);
  for (final MapEntry(:key, :value) in {...files, ...overrides}.entries) {
    dir.write(key, value);
  }
  final path = dir.write('typed_openapi.yaml', 'clients:\n$clients');
  final bag = DiagnosticBag();
  final config = ConfigLoader(bag).load(path)!;
  final checks = SpecChecker(bag, DisplayPaths(dir.path)).check(config);
  return (checks: checks, bag: bag, dir: dir);
}

List<Diagnostic> _of(DiagnosticBag bag, DiagnosticCode code) => [
  for (final d in bag.all)
    if (d.code == code) d,
];

const _pets = '''
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/pets]}
''';

void main() {
  group('findings outside the generated API', () {
    test('an invalid ref in an operation the include leaves out is info', () {
      final run = _run(_spec(), _pets);
      expect(run.checks.single.errors, 0);
      final invalid = _of(run.bag, DiagnosticCode.invalidRef).single;
      expect(invalid.severity, Severity.info);
      expect(invalid.pointer?.value, contains('/paths/~1links/get'));
      final note = _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi);
      expect(note, hasLength(1));
      expect(note.single.severity, Severity.info);
      expect(note.single.message, contains('1 finding'));
    });

    test('the same ref in an included operation still blocks', () {
      final run = _run(_spec(), '''
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/links]}
''');
      expect(run.checks.single.errors, 1);
      expect(
        _of(run.bag, DiagnosticCode.invalidRef).single.severity,
        Severity.error,
      );
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        isEmpty,
      );
    });

    test('a component shared with an included operation keeps its level', () {
      final spec = _spec(
        links: r"{$ref: '#/components/schemas/Bad'}",
        components:
            '''
    Bad:
      type: object
      properties: {x: $_brokenRef}
''',
        extraPaths:
            '''
  /shared:
    get:
      operationId: shared
      tags: [pets]
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$_dollarRef: '#/components/schemas/Bad'}
''',
      );
      final run = _run(spec, '''
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/pets, /shared]}
''');
      expect(run.checks.single.errors, 1);
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        isEmpty,
      );
    });

    test('a component only the excluded operation uses is lowered', () {
      final spec = _spec(
        links: r"{$ref: '#/components/schemas/Bad'}",
        components:
            '''
    Bad:
      type: object
      properties: {x: $_brokenRef}
''',
      );
      final run = _run(spec, _pets);
      expect(run.checks.single.errors, 0);
      expect(
        _of(run.bag, DiagnosticCode.invalidRef).single.severity,
        Severity.info,
      );
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi).single,
        isNotNull,
      );
    });

    test('exclude patterns lower the same way, with no include', () {
      final run = _run(_spec(), '''
  api:
    input: api.yaml
    output: lib/api
    exclude: {paths: [/links]}
''');
      expect(run.checks.single.errors, 0);
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        hasLength(1),
      );
    });

    test('an exclude: true override acts as the filter, without include', () {
      final run = _run(
        _spec(),
        '''
  api:
    input: api.yaml
    output: lib/api
    overrides: overrides.yaml
''',
        overrides: {
          'overrides.yaml': 'operations:\n  GET /links: {exclude: true}\n',
        },
      );
      expect(run.checks.single.errors, 0);
      final invalid = _of(run.bag, DiagnosticCode.invalidRef).single;
      expect(invalid.severity, Severity.info);
      final note = _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi);
      expect(note, hasLength(1));
      expect(note.single.file, 'api.yaml');
      expect(note.single.pointer?.value, '#/paths');
    });

    test('a subtype of a discriminated base keeps its level', () {
      final spec = _spec(
        links: r"{$ref: '#/components/schemas/Cat'}",
        components:
            '''
    Pet:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
      discriminator: {propertyName: kind}
    Cat:
      allOf:
        - {$_dollarRef: '#/components/schemas/Pet'}
        - type: object
          properties: {x: $_brokenRef}
''',
        extraPaths:
            '''
  /pet:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$_dollarRef: '#/components/schemas/Pet'}
''',
      );
      final run = _run(spec, '''
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/pet]}
''');
      expect(run.checks.single.errors, 1);
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        isEmpty,
      );
    });

    test('a warning in an excluded operation is lowered too', () {
      final spec = _spec(
        links: '{type: string}',
        extraPaths: '''
  /odd:
    get:
      operationId: odd
      tags: [odd]
      unknownThing: 1
      responses: {'204': {description: ok}}
''',
      );
      final run = _run(spec, _pets);
      final unknown = [
        for (final d in run.bag.all)
          if (d.pointer?.value.contains('~1odd') ?? false) d,
      ];
      expect(unknown, isNotEmpty);
      expect(unknown.map((d) => d.severity), everyElement(Severity.info));
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        hasLength(1),
      );
    });

    test('a diagnostic in the overrides file is untouched', () {
      final run = _run(
        _spec(),
        '''
  api:
    input: api.yaml
    output: lib/api
    overrides: overrides.yaml
    include: {paths: [/pets]}
''',
        overrides: {'overrides.yaml': 'operations:\n  GET /pets: {nope: 1}\n'},
      );
      final bad = _of(run.bag, DiagnosticCode.unknownOverrideKey);
      expect(bad.single.severity, Severity.error);
      expect(bad.single.file, 'overrides.yaml');
    });

    test('a client without filters is unchanged', () {
      final run = _run(_spec(), '''
  api: {input: api.yaml, output: lib/api}
''');
      expect(run.checks.single.errors, 1);
      expect(
        _of(run.bag, DiagnosticCode.findingsOutsideGeneratedApi),
        isEmpty,
      );
    });

    test('two clients over one spec are judged by their own filter', () {
      final run = _run(_spec(), '''
  pets:
    input: api.yaml
    output: lib/pets
    include: {paths: [/pets]}
  links:
    input: api.yaml
    output: lib/links
    include: {paths: [/links]}
''');
      expect(
        {for (final c in run.checks) c.client.name: c.errors},
        {'pets': 0, 'links': 1},
      );
    });

    test(
      'an error in a file only the excluded operation reaches is lowered',
      () {
        final spec = _spec(links: r"{$ref: 'other.yaml#/Bad'}");
        final run = _run(
          spec,
          _pets,
          files: {
            'other.yaml':
                'Bad:\n  type: object\n  properties:\n    x: $_brokenRef\n',
          },
        );
        expect(run.checks.single.errors, 0);
        final invalid = _of(run.bag, DiagnosticCode.invalidRef).single;
        expect(invalid.file, 'other.yaml');
        expect(invalid.severity, Severity.info);
      },
    );
  });
}
