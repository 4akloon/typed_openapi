import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/temp_dir.dart';

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
}
