import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/config_loader.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

List<ClientConfig> load(String text, DiagnosticBag bag) =>
    ConfigLoader(bag).load(TempDir().write('c.yaml', text))!.clients;

String config(String defaults, String client) =>
    '''
defaults:
$defaults
clients:
  a:
    input: a.json
    output: lib/a
$client
''';

List<(String, String?)> problems(DiagnosticBag bag) => [
  for (final d in bag.all)
    if (d.code == DiagnosticCode.configInvalid) (d.message, d.pointer?.value),
];

void main() {
  test('an invalid client value falls back to the value of defaults', () {
    final bag = DiagnosticBag();
    final clients = load(
      config('  union: structural', '    union: maybe'),
      bag,
    );
    expect(clients.single.generation.union, UnionMode.structural);
    expect(problems(bag), [
      (
        '"union" must be one of raw, structural. '
            'The value from "defaults" (structural) is used.',
        '#/clients/a/union',
      ),
    ]);
  });

  test('an invalid client value and an invalid default use the built-in', () {
    final bag = DiagnosticBag();
    final clients = load(config('  union: nope', '    union: maybe'), bag);
    expect(clients.single.generation.union, UnionMode.raw);
    const message =
        '"union" must be one of raw, structural. The default (raw) is used.';
    expect(problems(bag), [
      (message, '#/clients/a/union'),
      (message, '#/defaults/union'),
    ]);
  });

  test('an invalid default alone is reported at defaults', () {
    final bag = DiagnosticBag();
    final clients = load(
      config('  tri_state: nope', '    union: structural'),
      bag,
    );
    expect(clients.single.generation.triState, TriStateRule.patch);
    expect(problems(bag).map((p) => p.$2), ['#/defaults/tri_state']);
  });

  test('a valid client value wins and nothing is reported', () {
    final bag = DiagnosticBag();
    final clients = load(
      config('  exhaustive: false', '    exhaustive: true'),
      bag,
    );
    expect(clients.single.generation.exhaustive, isTrue);
    expect(problems(bag), isEmpty);
  });

  test('every setting falls back to defaults, key by key', () {
    final bag = DiagnosticBag();
    final clients = load(
      config(
        '''
  group_by: path
  tri_state: optional
  union: structural
  exhaustive: false
  naming: {stream_suffix: Events}
  types: {number: int}
  errors: {default_schema: Problem}
  sse: {reconnect: true}''',
        '''
    group_by: nope
    tri_state: nope
    union: nope
    exhaustive: nope
    naming: {stream_suffix: bad suffix}
    types: {number: nope}
    errors: {default_schema: ''}
    sse: {reconnect: nope}''',
      ),
      bag,
    );
    final generation = clients.single.generation;
    expect(generation.groupBy, GroupBy.path);
    expect(generation.triState, TriStateRule.optional);
    expect(generation.union, UnionMode.structural);
    expect(generation.exhaustive, isFalse);
    expect(generation.streamSuffix, 'Events');
    expect(generation.numberType, 'int');
    expect(generation.defaultErrorSchema, 'Problem');
    expect(generation.streamReconnect, isTrue);
    final reported = problems(bag);
    expect(reported, hasLength(8));
    for (final (message, _) in reported) {
      expect(message, contains('The value from "defaults"'));
    }
  });

  test('the message names a built-in that is not a plain word', () {
    final bag = DiagnosticBag();
    load(config('  {}', '    naming: {stream_suffix: bad suffix}'), bag);
    expect(problems(bag).single.$1, endsWith('The default (Stream) is used.'));
  });

  test('an invalid include filter falls back to the filter of defaults', () {
    final bag = DiagnosticBag();
    final clients = load(
      config('  include: {tags: [a]}', '    include: {tags: nope}'),
      bag,
    );
    expect(clients.single.generation.include.tags.map((t) => t.value), ['a']);
  });

  test('equal suffixes revert both to the defaults, as before', () {
    final bag = DiagnosticBag();
    final clients = load(
      config('  {}', '    naming: {input_suffix: Same, patch_suffix: Same}'),
      bag,
    );
    expect(clients.single.generation.inputSuffix, 'Input');
    expect(clients.single.generation.patchSuffix, 'Patch');
    expect(problems(bag), hasLength(1));
  });
}
