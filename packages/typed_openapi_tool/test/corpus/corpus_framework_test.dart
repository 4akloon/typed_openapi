@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_list_reader.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_spec.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  String corpus(String extra) =>
      '''
specs:
  pets:
    url: https://example.com/a.yaml
    sha256: $_hash
    license: MIT
    expect: generate
$extra''';

  CorpusSpec read(String extra) =>
      const CorpusListReader().read(corpus(extra)).single;

  test('an entry without a framework is generic and expects detection', () {
    final spec = read('');
    expect(spec.framework, Preset.generic);
    expect(spec.detects, isTrue);
  });

  test('framework names a preset, detects: false says it is not marked', () {
    final spec = read('    framework: aspnet\n    detects: false\n');
    expect(spec.framework, Preset.aspnet);
    expect(spec.detects, isFalse);
    expect(spec.expectedPreset, Preset.generic);
  });

  test('an unknown framework names the known ones', () {
    expect(
      () => read('    framework: rails\n'),
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          contains('known: generic, nestjs, fastapi, springdoc, aspnet'),
        ),
      ),
    );
  });

  test('detects is a boolean, and false only with a framework', () {
    for (final extra in [
      '    framework: nestjs\n    detects: 3\n',
      '    framework: nestjs\n    detects: maybe\n',
      '    detects: false\n',
      '    framework: generic\n    detects: false\n',
    ]) {
      expect(() => read(extra), throwsA(isA<CorpusException>()), reason: extra);
    }
  });

  test('the corpus names the framework of the code-first specs', () {
    final specs = {
      for (final spec in const CorpusListReader().read(
        File('corpus.yaml').readAsStringSync(),
      ))
        spec.name: spec,
    };
    expect(
      {
        for (final name in [
          'airflow',
          'artemis',
          'efgs',
          'springdoc',
          'jellyfin',
          'swashbuckle',
          'immich',
          'tambo',
        ])
          name: specs[name]!.framework,
      },
      {
        'airflow': Preset.fastapi,
        'artemis': Preset.springdoc,
        'efgs': Preset.springdoc,
        'springdoc': Preset.springdoc,
        'jellyfin': Preset.aspnet,
        'swashbuckle': Preset.aspnet,
        'immich': Preset.nestjs,
        'tambo': Preset.nestjs,
      },
    );
    expect(specs['swashbuckle']!.detects, isFalse);
  });
}
