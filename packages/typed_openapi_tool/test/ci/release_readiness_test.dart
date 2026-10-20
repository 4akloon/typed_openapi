import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Reads the pubspecs of the packages next to the tool.
class _Pubspecs {
  /// Creates the reader.
  const _Pubspecs();

  /// The parsed `pubspec.yaml` of the package [name].
  YamlMap of(String name) =>
      loadYaml(File(p.join('..', name, 'pubspec.yaml')).readAsStringSync())
          as YamlMap;
}

void main() {
  const published = [
    'typed_openapi_core',
    'typed_openapi_client',
    'typed_openapi',
    'typed_openapi_dio',
  ];
  const unpublished = [
    'typed_openapi_tool',
    'typed_openapi_test_support',
    'typed_openapi_transport_tests',
  ];

  for (final name in published) {
    group(name, () {
      test('has the pub.dev metadata', () {
        final pubspec = const _Pubspecs().of(name);
        expect(
          pubspec['issue_tracker'],
          'https://github.com/4akloon/typed_openapi/issues',
        );
        expect(pubspec['repository'], isNotNull);
        final topics = (pubspec['topics'] as YamlList).cast<String>();
        expect(topics, isNotEmpty);
        expect(topics.length, lessThanOrEqualTo(5));
        for (final topic in topics) {
          expect(topic, matches(RegExp(r'^[a-z][a-z0-9-]{1,31}$')));
        }
      });

      test('has an example', () {
        final example = Directory(p.join('..', name, 'example'));
        expect(example.existsSync(), isTrue);
        expect(example.listSync(), isNotEmpty);
      });

      test('names its version at the top of the CHANGELOG', () {
        final changelog = File(
          p.join('..', name, 'CHANGELOG.md'),
        ).readAsStringSync();
        expect(
          changelog,
          startsWith('## ${const _Pubspecs().of(name)['version']}'),
        );
      });
    });
  }

  test('dev dependencies on a sibling ask for its version too', () {
    final version = const _Pubspecs().of('typed_openapi')['version'];
    for (final name in published) {
      final dev = const _Pubspecs().of(name)['dev_dependencies'] as YamlMap;
      for (final other in published.where((other) => other != name)) {
        if (!dev.containsKey(other)) continue;
        expect(dev[other], '^$version', reason: '$name dev-depends on $other');
      }
    }
  });

  test('a published package asks no unpublished package for anything', () {
    for (final name in published) {
      final dependencies =
          const _Pubspecs().of(name)['dependencies'] as YamlMap;
      for (final other in unpublished) {
        expect(dependencies.containsKey(other), isFalse, reason: name);
      }
    }
  });

  test('every published package has a tag in publish.yml', () {
    final workflow =
        loadYaml(
              File(
                p.join('..', '..', '.github', 'workflows', 'publish.yml'),
              ).readAsStringSync(),
            )
            as YamlMap;
    // YAML 1.1 would read the key `on` as true; this parser keeps the text.
    final trigger = (workflow['on'] ?? workflow[true]) as YamlMap;
    final tags = ((trigger['push'] as YamlMap)['tags'] as YamlList)
        .cast<String>();
    expect(tags, unorderedEquals([for (final name in published) '$name-v*']));
  });
}
