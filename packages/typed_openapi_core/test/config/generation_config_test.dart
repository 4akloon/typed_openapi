import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/config_loader.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  List<ClientConfig> load(String text, DiagnosticBag bag) =>
      ConfigLoader(bag).load(TempDir().write('c.yaml', text))!.clients;

  test('defaults every generation setting', () {
    final bag = DiagnosticBag();
    final config = load('''
clients:
  a: {input: a.json, output: lib/a}
''', bag).single.generation;
    expect(bag.all, isEmpty);
    expect(config.groupTemplate, '{Tag}Api');
    expect(config.defaultGroup, 'DefaultApi');
    expect(config.inputSuffix, 'Input');
    expect(config.patchSuffix, 'Patch');
    expect(config.operationPrefix, isNull);
    expect(config.groupBy, GroupBy.tag);
    expect(config.include.isEmpty, isTrue);
    expect(config.numberType, isNull);
    expect(config.triState, TriStateRule.patch);
    expect(config.defaultErrorSchema, isNull);
  });

  test('reads every setting; a client overrides defaults key by key', () {
    final bag = DiagnosticBag();
    final clients = load('''
defaults:
  naming: {group: '{Tag}Service', input_suffix: Request, patch_suffix: Changes}
  group_by: path
  types:
    number: double
    formats:
      decimal: {type: Decimal, import: 'package:decimal/decimal.dart'}
  errors: {default_schema: ErrorDto}
clients:
  a:
    input: a.json
    output: lib/a
    naming: {operation_prefix: '^[A-Za-z0-9]*Controller_'}
    include: {tags: [pets], paths: ['/pets/**']}
    exclude: {operations: [deletePet]}
    types:
      schemas:
        Money: {type: Money, import: 'package:app/money.dart', converter: MoneyConverter}
    tri_state: optional
  b: {input: b.json, output: lib/b, group_by: single}
''', bag);
    expect(bag.all, isEmpty);
    final a = clients.first.generation;
    expect(a.groupTemplate, '{Tag}Service');
    expect(a.inputSuffix, 'Request');
    expect(a.patchSuffix, 'Changes');
    expect(a.operationPrefix?.pattern, '^[A-Za-z0-9]*Controller_');
    expect(a.groupBy, GroupBy.path);
    expect(a.include.tags.single.value, 'pets');
    expect(a.include.paths.single.pointer.value, '#/clients/a/include/paths/0');
    expect(a.exclude.operations.single.value, 'deletePet');
    expect(a.numberType, 'double');
    expect(a.formats['decimal']?.type, 'Decimal');
    expect(a.schemas['Money']?.converter, 'MoneyConverter');
    expect(a.triState, TriStateRule.optional);
    expect(a.defaultErrorSchema, 'ErrorDto');
    final b = clients.last.generation;
    expect(b.groupBy, GroupBy.single);
    expect(b.groupTemplate, '{Tag}Service');
    expect(b.schemas, isEmpty);
    expect(a.key == b.key, isFalse);
  });

  test('reports invalid generation settings and uses the defaults', () {
    final bag = DiagnosticBag();
    final config = load('''
clients:
  a:
    input: a.json
    output: lib/a
    naming: {group: Api, default_group: 'my api', operation_prefix: '(', bogus: 1}
    group_by: tags
    include: {tags: pets}
    types:
      number: float
      formats: {decimal: {type: Decimal}}
    tri_state: maybe
''', bag).single.generation;
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configUnknownKey, '#/clients/a/naming/bogus'),
      (DiagnosticCode.configInvalid, '#/clients/a/naming/group'),
      (DiagnosticCode.configInvalid, '#/clients/a/naming/default_group'),
      (DiagnosticCode.configInvalid, '#/clients/a/naming/operation_prefix'),
      (DiagnosticCode.configInvalid, '#/clients/a/group_by'),
      (DiagnosticCode.configInvalid, '#/clients/a/include/tags'),
      (DiagnosticCode.configInvalid, '#/clients/a/types/number'),
      (DiagnosticCode.configInvalid, '#/clients/a/types/formats/decimal'),
      (DiagnosticCode.configInvalid, '#/clients/a/tri_state'),
    ]);
    expect(config.groupTemplate, '{Tag}Api');
    expect(config.defaultGroup, 'DefaultApi');
    expect(config.groupBy, GroupBy.tag);
    expect(config.formats, isEmpty);
    expect(config.triState, TriStateRule.patch);
  });
  test('reserved words are no default_group; equal suffixes are an error', () {
    final bag = DiagnosticBag();
    final clients = load('''
clients:
  a: {input: a.json, output: lib/a, naming: {default_group: class}}
  b: {input: b.json, output: lib/b, naming: {default_group: abstract}}
  c: {input: c.json, output: lib/c, naming: {input_suffix: Body, patch_suffix: Body}}
  d: {input: d.json, output: lib/d, naming: {input_suffix: Patch}}
  e: {input: e.json, output: lib/e, naming: {input_suffix: Request, patch_suffix: Changes}}
''', bag);
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configInvalid, '#/clients/a/naming/default_group'),
      (DiagnosticCode.configInvalid, '#/clients/b/naming/default_group'),
      (DiagnosticCode.configInvalid, '#/clients/c/naming/patch_suffix'),
      (DiagnosticCode.configInvalid, '#/clients/d/naming/input_suffix'),
    ]);
    expect(bag.all.first.message, contains('reserved word'));
    expect(bag.all[2].message, contains('different'));
    expect(clients[0].generation.defaultGroup, 'DefaultApi');
    expect(clients[1].generation.defaultGroup, 'DefaultApi');
    expect(clients[2].generation.inputSuffix, 'Input');
    expect(clients[2].generation.patchSuffix, 'Patch');
    expect(clients[3].generation.inputSuffix, 'Input');
    expect(clients[3].generation.patchSuffix, 'Patch');
    expect(clients[4].generation.inputSuffix, 'Request');
    expect(clients[4].generation.patchSuffix, 'Changes');
  });

  group('exhaustive', () {
    test('is true by default; a client overrides defaults', () {
      final bag = DiagnosticBag();
      final clients = load('''
defaults: {exhaustive: false}
clients:
  a: {input: a.json, output: lib/a}
  b: {input: a.json, output: lib/b, exhaustive: true}
  c: {input: a.json, output: lib/c}
''', bag);
      expect(bag.all, isEmpty);
      expect(
        [for (final c in clients) c.generation.exhaustive],
        [
          false,
          true,
          false,
        ],
      );
      expect(const GenerationConfig().exhaustive, isTrue);
    });

    test('a value that is not a bool is TOA902 and true is used', () {
      final bag = DiagnosticBag();
      final config = load('''
clients:
  a: {input: a.json, output: lib/a, exhaustive: maybe}
''', bag).single.generation;
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (DiagnosticCode.configInvalid, '#/clients/a/exhaustive'),
      ]);
      expect(config.exhaustive, isTrue);
    });

    test('changes the key only when false', () {
      final clients = load('''
clients:
  a: {input: a.json, output: lib/a}
  b: {input: a.json, output: lib/b, exhaustive: true}
  c: {input: a.json, output: lib/c, exhaustive: false}
''', DiagnosticBag());
      expect(clients[0].generation.key, clients[1].generation.key);
      expect(clients[0].generation.key, isNot(clients[2].generation.key));
      expect(clients[0].generation.key, isNot(contains('exhaustive')));
    });
  });

  group('key', () {
    test('does not depend on the order of custom types', () {
      final bag = DiagnosticBag();
      final clients = load('''
defaults:
  types:
    formats: {b: {type: B, import: 'package:x/b.dart'}}
clients:
  a:
    input: a.json
    output: lib/a
    types:
      formats: {a: {type: A, import: 'package:x/a.dart'}}
      schemas: {Y: {type: Y, import: 'package:x/y.dart'}, X: {type: X, import: 'package:x/x.dart'}}
  b:
    input: a.json
    output: lib/b
    types:
      formats: {a: {type: A, import: 'package:x/a.dart'}, b: {type: B, import: 'package:x/b.dart'}}
      schemas: {X: {type: X, import: 'package:x/x.dart'}, Y: {type: Y, import: 'package:x/y.dart'}}
''', bag);
      expect(bag.all, isEmpty);
      expect(clients[0].generation.key, clients[1].generation.key);
    });

    test('is the same for clients without a filter', () {
      final clients = load('''
clients:
  a: {input: a.json, output: lib/a}
  b: {input: a.json, output: lib/b}
''', DiagnosticBag());
      expect(clients[0].generation.key, clients[1].generation.key);
    });

    test('differs for clients with a filter: it is reported at its client', () {
      final clients = load('''
defaults:
  include: {tags: [pets]}
clients:
  a: {input: a.json, output: lib/a}
  b: {input: a.json, output: lib/b}
  c: {input: a.json, output: lib/c, exclude: {paths: ['/x']}}
''', DiagnosticBag());
      final keys = {for (final c in clients) c.generation.key};
      expect(keys, hasLength(3));
    });
  });
}
