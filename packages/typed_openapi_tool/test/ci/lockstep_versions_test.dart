import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The parsed `pubspec.yaml` of the package [name] next to the tool.
YamlMap pubspecOf(String name) =>
    loadYaml(File(p.join('..', name, 'pubspec.yaml')).readAsStringSync())
        as YamlMap;

void main() {
  const published = [
    'typed_openapi_core',
    'typed_openapi_client',
    'typed_openapi',
    'typed_openapi_dio',
  ];

  test('the published packages share one version', () {
    final versions = {
      for (final name in published) pubspecOf(name)['version'],
    };
    expect(versions, hasLength(1));
  });

  test('a published package asks for the version of the ones it uses', () {
    final version = pubspecOf('typed_openapi')['version'];
    for (final name in published) {
      final dependencies = pubspecOf(name)['dependencies'] as YamlMap;
      for (final other in published.where((other) => other != name)) {
        if (!dependencies.containsKey(other)) continue;
        expect(
          dependencies[other],
          '^$version',
          reason: '$name depends on $other',
        );
      }
    }
  });
}
