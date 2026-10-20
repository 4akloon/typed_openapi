import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The node at [path] of the workflow file [name] in `.github/workflows`.
Object? at(String name, List<Object> path) {
  final file = File(p.join('..', '..', '.github', 'workflows', name));
  Object? node = loadYaml(file.readAsStringSync());
  for (final key in path) {
    node = switch ((node, key)) {
      (final Map<Object?, Object?> map, _) => map[key],
      (final List<Object?> list, final int index) => list[index],
      _ => null,
    };
  }
  return node;
}

/// The `run` lines of the steps of the job [job] of the workflow [name].
List<String> runsOf(String name, String job) => [
  for (final step in at(name, ['jobs', job, 'steps']) as List<Object?>)
    if (step case {'run': final String run}) run,
];

/// The distinct working directories of the steps of the job [job] of the
/// workflow [name], in order.
List<String> directoriesOf(String name, String job) => {
  for (final step in at(name, ['jobs', job, 'steps']) as List<Object?>)
    if (step case {'working-directory': final String directory}) directory,
}.toList();

void main() {
  test('every job of every workflow has a timeout', () {
    final folder = Directory(p.join('..', '..', '.github', 'workflows'));
    for (final file in folder.listSync().whereType<File>()) {
      final name = p.basename(file.path);
      final jobs = at(name, ['jobs']) as Map<Object?, Object?>;
      for (final job in jobs.keys) {
        expect(
          at(name, ['jobs', job as Object, 'timeout-minutes']),
          isA<int>(),
          reason: '$name: job $job',
        );
      }
    }
  });

  test('every PR tests ubuntu with 3.10.0 and stable, macOS and Windows', () {
    const matrix = ['jobs', 'analyze-test', 'strategy', 'matrix'];
    expect(at('ci.yml', [...matrix, 'sdk']), ['3.10.0', 'stable']);
    expect(at('ci.yml', [...matrix, 'include', 0, 'os']), 'macos-latest');
    expect(at('ci.yml', [...matrix, 'include', 1, 'os']), 'windows-latest');
  });

  test('the tool tests run after the SARIF schema is fetched', () {
    final runs = runsOf('ci.yml', 'analyze-test');
    final fetch = runs.indexOf('dart run bin/corpus.dart fetch sarif_schema');
    expect(fetch, isNonNegative);
    // The tool tests are the last `dart test` of the job.
    expect(runs.lastIndexOf('dart test'), greaterThan(fetch));
  });

  test('every PR runs the runtime on dart2js and dart2wasm', () {
    expect(at('ci.yml', ['jobs', 'web', 'strategy', 'matrix', 'compiler']), [
      'dart2js',
      'dart2wasm',
    ]);
  });

  test('every PR tests the Dio adapter on the VM and in Chrome', () {
    expect(directoriesOf('ci.yml', 'analyze-test'), [
      'packages/typed_openapi_core',
      'packages/typed_openapi',
      'packages/typed_openapi_client',
      'packages/typed_openapi_dio',
      'packages/typed_openapi_tool',
    ]);
    expect(directoriesOf('ci.yml', 'web'), [
      'packages/typed_openapi_client',
      'packages/typed_openapi_dio',
    ]);
  });

  test('the core is tested, dry-run before the generator, and has a tag', () {
    final dryRuns = directoriesOf('ci.yml', 'publish-dry-run');
    expect(dryRuns, contains('packages/typed_openapi_core'));
    expect(
      dryRuns.indexOf('packages/typed_openapi_core'),
      lessThan(dryRuns.indexOf('packages/typed_openapi')),
    );
    expect(
      at('publish.yml', ['on', 'push', 'tags']),
      contains('typed_openapi_core-v*'),
    );
  });

  test('the Dio adapter is dry-run and published by its tag', () {
    expect(
      directoriesOf('ci.yml', 'publish-dry-run'),
      contains('packages/typed_openapi_dio'),
    );
    expect(
      at('publish.yml', ['on', 'push', 'tags']),
      contains('typed_openapi_dio-v*'),
    );
  });

  test('every PR checks the corpus with both SDKs, the fuzz and semver', () {
    expect(at('ci.yml', ['jobs', 'corpus', 'strategy', 'matrix', 'sdk']), [
      '3.10.0',
      'stable',
    ]);
    expect(
      runsOf('ci.yml', 'corpus'),
      contains('dart run bin/corpus.dart check'),
    );
    expect(
      runsOf('ci.yml', 'corpus'),
      contains(contains('dart test test/sarif/sarif_validity_test.dart')),
    );
    expect(runsOf('ci.yml', 'fuzz'), contains(contains('--seeds 200')));
    expect(
      runsOf('ci.yml', 'semver'),
      contains(contains('corpus.dart semver')),
    );
  });

  test('nightly runs beta as a warning, the corpus on Windows, 6000 seeds', () {
    expect(at('nightly.yml', ['jobs', 'beta', 'continue-on-error']), isTrue);
    expect(
      at('nightly.yml', ['jobs', 'corpus-windows', 'runs-on']),
      'windows-latest',
    );
    expect(runsOf('nightly.yml', 'fuzz'), contains(contains('--seeds 6000')));
  });

  test('workflows can only read the repository', () {
    for (final name in ['ci.yml', 'nightly.yml']) {
      expect(at(name, ['permissions']), {'contents': 'read'}, reason: name);
    }
  });

  test('semver sees the full history and runs on pull requests only', () {
    expect(at('ci.yml', ['jobs', 'semver', 'if']), contains('pull_request'));
    expect(
      at('ci.yml', ['jobs', 'semver', 'steps', 0, 'with', 'fetch-depth']),
      0,
    );
  });

  test('only the nightly beta job may fail without failing the run', () {
    for (final name in ['ci.yml', 'nightly.yml']) {
      final jobs = at(name, ['jobs']) as Map<Object?, Object?>;
      final lenient = [
        for (final MapEntry(:key, :value) in jobs.entries)
          if ((value as Map<Object?, Object?>).containsKey('continue-on-error'))
            key,
      ];
      expect(lenient, name == 'nightly.yml' ? ['beta'] : isEmpty);
    }
  });
}
