import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('checks every client and names files relative to the working '
      'directory', () {
    final dir = TempDir();
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.0.3\ninfo: {title: ok, version: "1"}\npaths: {}\n',
    );
    dir.write('specs/old.json', '{"swagger": "2.0"}');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  ok: {input: specs/ok.yaml, output: lib/ok}
  old: {input: specs/old.json, output: lib/old}
  missing: {input: specs/missing.yaml, output: lib/missing}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    expect(
      bag.all.map((d) => (d.code, d.file)),
      unorderedEquals([
        (DiagnosticCode.inputNotFound, 'specs/missing.yaml'),
        (DiagnosticCode.unsupportedOpenApiVersion, 'specs/old.json'),
      ]),
    );
  });

  test('normalizes each spec with the client\'s rules', () {
    final dir = TempDir();
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''';
    dir.write('a.yaml', spec);
    dir.write('b.yaml', spec);
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b:
    input: b.yaml
    output: lib/b
    rules: {bool-required-to-array: false}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.boolRequired, 'a.yaml'),
      (DiagnosticCode.invalidValue, 'b.yaml'),
    ]);
  });

  test("applies each client's overrides before the rules", () {
    final dir = TempDir();
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    File: {type: object, format: binary}
''';
    dir.write('specs/api.yaml', spec);
    dir.write('specs/api.overrides.yaml', 'schemas: {File: {type: string}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  fixed:
    input: specs/api.yaml
    output: lib/fixed
    overrides: specs/api.overrides.yaml
  plain: {input: specs/api.yaml, output: lib/plain}
  broken:
    input: specs/api.yaml
    output: lib/broken
    overrides: specs/missing.yaml
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(
      bag.all.map((d) => (d.code, d.file)),
      unorderedEquals([
        (DiagnosticCode.overridesNotFound, 'specs/missing.yaml'),
        (DiagnosticCode.binaryObject, 'specs/api.yaml'),
      ]),
    );
  });

  test('only checks the named clients', () {
    final dir = TempDir();
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b: {input: b.yaml, output: lib/b}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag, DisplayPaths(dir.path)).check(config, only: {'a'});
    expect(bag.all.single.file, 'a.yaml');
  });

  test('checks a spec shared by several clients once', () {
    final dir = TempDir();
    dir.write('shared.json', '{"swagger": "2.0"}');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: shared.json, output: lib/a}
  b: {input: shared.json, output: lib/b}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
  });

  test('a shared spec is checked once per preset and rule set', () {
    final dir = TempDir();
    dir.write('shared.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: shared.yaml, output: lib/a}
  b:
    input: shared.yaml
    output: lib/b
    rules: {bool-required-to-array: false}
  c: {input: shared.yaml, output: lib/c}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    // a and c share one run (TOA201); b runs without the fix (TOA111).
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.boolRequired,
      DiagnosticCode.invalidValue,
    ]);
  });

  test('reads each spec into the model and follows its references', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.0.3
info: {title: api}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses:
        "200": {$ref: "common.yaml#/components/responses/Missing"}
''');
    dir.write('specs/common.yaml', 'components: {responses: {}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: specs/api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    expect(
      bag.sorted.map((d) => (d.code, d.file, d.pointer?.value)),
      [
        (DiagnosticCode.missingRequiredField, 'specs/api.yaml', '#/info'),
        (
          DiagnosticCode.unresolvedRef,
          'specs/api.yaml',
          r'#/paths/~1pets/get/responses/200/$ref',
        ),
      ],
    );
  });

  test('a side file shared by two clients is reported once', () {
    final dir = TempDir();
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "common.yaml#/Err"}}}
''';
    dir.write('a.yaml', spec);
    dir.write('b.yaml', spec);
    dir.write('common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b: {input: b.yaml, output: lib/b}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file, d.pointer?.value)), [
      (DiagnosticCode.unknownKey, 'common.yaml', '#/Err/bogus'),
    ]);
  });

  test('reports the dialect of a spec against its declared version', () {
    final dir = TempDir();
    dir.write('api.json', '''
{
  "openapi": "3.1.0",
  "info": {"title": "api", "version": "1"},
  "components": {"schemas": {"A": {"type": "string", "nullable": true}}}
}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.json, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });

  test('does not read a spec whose version it cannot detect', () {
    final dir = TempDir();
    dir.write('api.yaml', 'info: {title: 5}\nnmae: x\n');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });

  test('names files by the working directory, not the config', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "common.yaml#/Err"}}}
''');
    dir.write('specs/common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('config/typed_openapi.yaml', '''
clients:
  api: {input: ../specs/api.yaml, output: ../lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.unknownKey, p.join('specs', 'common.yaml')),
    ]);
  });

  test('names a file outside the working directory by its absolute path', () {
    final dir = TempDir();
    dir.write('project/api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "../shared/common.yaml#/Err"}}}
''');
    dir.write('shared/common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('project/typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(p.join(dir.path, 'project')),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (
        DiagnosticCode.unknownKey,
        p.normalize(p.join(dir.path, 'shared', 'common.yaml')),
      ),
    ]);
  });

  test("gives each client's diagnostics its levels", () {
    final dir = TempDir();
    dir.write('shared.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: shared.yaml, output: lib/a, severity: {bool-required: error}}
  b: {input: shared.yaml, output: lib/b, severity: {bool-required: off}}
  c: {input: shared.yaml, output: lib/c}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    // One run: a raises the finding, b turns it off, c keeps the default.
    expect(bag.all.map((d) => (d.code, d.severity)), [
      (DiagnosticCode.boolRequired, Severity.error),
      (DiagnosticCode.boolRequired, Severity.warning),
    ]);
    expect(bag.hasErrors, isTrue);
  });

  test('a code turned off leaves nothing in the report', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
    final path = dir.write('typed_openapi.yaml', '''
defaults: {severity: {TOA201: off}}
clients:
  api: {input: api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all, isEmpty);
  });

  group('baseline', () {
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
        id: {type: string, required: true}
''';

    DiagnosticBag check(String baseline, {bool strict = false}) {
      final dir = TempDir();
      dir.write('api.yaml', spec);
      dir.write('api.baseline.yaml', baseline);
      final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
''');
      final bag = DiagnosticBag();
      SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).check(ConfigLoader(bag).load(path)!, strictBaseline: strict);
      return bag;
    }

    const name = '@/schemas/Tag/properties/name#/required';
    final nameFingerprint = Fingerprints.hash(
      DiagnosticCode.boolRequired,
      name,
      const [],
    );

    test('hides accepted diagnostics and shows the rest', () {
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint", code: TOA201, anchor: "$name"}
''');
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Tag/properties/id/required',
        ),
      ]);
      expect(bag.baselined.map((d) => d.pointer?.value), [
        '#/components/schemas/Tag/properties/name/required',
      ]);
    });

    test('an entry with nothing to match is stale; strict makes it an '
        'error', () {
      const stale = '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''';
      final bag = check(stale);
      final entry = bag.all.where(
        (d) => d.code == DiagnosticCode.baselineEntryStale,
      );
      expect(entry.single.severity, Severity.warning);
      expect(entry.single.file, 'api.baseline.yaml');
      expect(entry.single.pointer?.value, '#/entries/0');
      expect(entry.single.line, 3);
      expect(
        check(stale, strict: true).all
            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
            .single
            .severity,
        Severity.error,
      );
    });

    test('an entry that accepts more than the check finds is stale', () {
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint", count: 3}
''');
      expect(bag.baselined.length, 1);
      expect(
        bag.all
            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
            .single
            .message,
        'This entry accepts 3 diagnostics (A diagnostic at $nameFingerprint), '
        'but the check finds 1.',
      );
    });

    test('a valid baseline that matches everything reports nothing', () {
      final id = Fingerprints.hash(
        DiagnosticCode.boolRequired,
        '@/schemas/Tag/properties/id#/required',
        const [],
      );
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint"}
  - {fingerprint: "$id"}
''');
      expect(bag.all, isEmpty);
      expect(bag.baselined.length, 2);
    });

    test('strict applies after the levels of the config', () {
      const stale = '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''';
      for (final level in ['off', 'info']) {
        final dir = TempDir();
        dir.write('api.yaml', spec);
        dir.write('api.baseline.yaml', stale);
        final path = dir.write('typed_openapi.yaml', '''
clients:
  api:
    input: api.yaml
    output: lib/api
    baseline: api.baseline.yaml
    severity: {baseline-entry-stale: $level}
''');
        final bag = DiagnosticBag();
        SpecChecker(
          bag,
          DisplayPaths(dir.path),
        ).check(ConfigLoader(bag).load(path)!, strictBaseline: true);
        expect(
          bag.all
              .where((d) => d.code == DiagnosticCode.baselineEntryStale)
              .map((d) => d.severity),
          [Severity.error],
          reason: level,
        );
      }
    });

    test('an unreadable spec reports its error and no stale entries', () {
      final dir = TempDir();
      dir.write('api.yaml', 'openapi: [3\n');
      dir.write('api.baseline.yaml', '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''');
      final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
''');
      final bag = DiagnosticBag();
      SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).check(ConfigLoader(bag).load(path)!);
      expect(bag.all.map((d) => d.code), [DiagnosticCode.parseError]);
    });

    test('a broken baseline file hides nothing', () {
      final bag = check('version: 2\nentries: []\n');
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.boolRequired,
        DiagnosticCode.boolRequired,
        DiagnosticCode.invalidBaseline,
      ]);
      expect(bag.baselined, isEmpty);
    });
  });

  test('clients with different presets keep both hints on a shared '
      'finding', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components: {schemas: {Kind: {type: string, enum: [a, a]}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b, preset: nestjs}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    final finding = bag.all.single;
    expect(finding.code, DiagnosticCode.duplicateEnumValue);
    expect(finding.fix, contains('In NestJS, give the enum its own schema'));
    expect(finding.fix, isNot(contains('nestjs:')));
  });

  test('hints of several presets are named by their preset', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a: {get: {operationId: same, tags: [a], responses: {'200': {description: ok}}}}
  /b: {get: {operationId: same, tags: [b], responses: {'200': {description: ok}}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a, preset: nestjs}
  b: {input: api.yaml, output: lib/b, preset: fastapi}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    final finding = bag.all.single;
    expect(finding.code, DiagnosticCode.duplicateOperationId);
    expect(
      finding.fix,
      'Give each operation its own operationId at the source, or override '
      'the method name of this operation. nestjs: In NestJS, set '
      '`operationIdFactory` in SwaggerModule.createDocument (the default is '
      'controllerKey_methodKey). fastapi: In FastAPI, pass '
      '`generate_unique_id_function` to FastAPI(...).',
    );
  });

  test('builds the IR of each client and reports its diagnostics', () {
    final dir = TempDir();
    dir.write('api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /lists:
    get:
      operationId: getLists
      tags: [lists]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/List'}}}}
components:
  schemas:
    List: {type: object, properties: {id: {type: integer}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b, naming: {group: '{Tag}Service'}}
''');
    final bag = DiagnosticBag();
    final checks = SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).checkClients(ConfigLoader(bag).load(path)!);
    expect(bag.all, isEmpty);
    expect(
      checks.map((c) => c.diagnostics.map((d) => (d.code, d.pointer?.value))),
      [
        [(DiagnosticCode.nameReserved, '#/components/schemas/List')],
        [(DiagnosticCode.nameReserved, '#/components/schemas/List')],
      ],
    );
    expect(checks.map((c) => c.ir!.groups.single.name), [
      'ListsApi',
      'ListsService',
    ]);
    expect(checks.first.ir!.declarations.single.name, 'ListModel');
    expect(
      checks.first.irJson!.toJson(checks.first.ir!)['declarations'],
      [
        {
          'name': 'ListModel',
          'at': 'api.yaml#/components/schemas/List',
          'kind': 'model',
          'direction': 'response',
          'fields': [
            {'name': 'id', 'json': 'id', 'type': 'int?'},
          ],
        },
      ],
    );
  });

  group('runs', () {
    const spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /lists:
    get:
      operationId: getLists
      tags: [lists]
      responses:
        "200": {description: ok}
''';

    List<ClientCheck> check(String clients) {
      final dir = TempDir();
      dir.write('api.yaml', spec);
      final path = dir.write('typed_openapi.yaml', clients);
      final bag = DiagnosticBag();
      return SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).checkClients(ConfigLoader(bag).load(path)!);
    }

    test('clients with identical settings share one run', () {
      final checks = check('''
clients:
  a: {input: api.yaml, output: lib/a, naming: {client: Api}}
  b: {input: api.yaml, output: lib/b, naming: {client: Api}}
''');
      expect(identical(checks[0].ir, checks[1].ir), isTrue);
    });

    test('clients that differ only where their filters are written do not '
        'share one', () {
      final checks = check('''
clients:
  a: {input: api.yaml, output: lib/a, include: {tags: [nope]}}
  b: {input: api.yaml, output: lib/b, include: {tags: [nope]}}
''');
      expect(identical(checks[0].ir, checks[1].ir), isFalse);
      expect(
        [
          for (final c in checks)
            for (final d in c.diagnostics)
              if (d.code == DiagnosticCode.filterMatchesNothing)
                d.pointer?.value,
        ],
        ['#/clients/a/include/tags/0', '#/clients/b/include/tags/0'],
      );
    });
  });
}
