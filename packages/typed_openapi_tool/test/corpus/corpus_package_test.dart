@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_package.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_run.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/package_gate.dart';

import '../helpers/corpus_entry.dart';

const _spec = '''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''';

void main() {
  test('the client keys of the config are quoted', () {
    final temp = TempDir();
    CorpusPackage(temp.path, 'raw').write({
      'yes': '/specs/yes.yaml',
      '123': '/specs/123.yaml',
    }, '/runtime');
    final config = File(p.join(temp.path, 'typed_openapi.yaml'));
    expect(config.readAsStringSync(), contains("  'yes':\n"));
    expect(config.readAsStringSync(), contains("  '123':\n"));
  });

  test('a non-empty directory the tool did not make is refused untouched', () {
    final temp = TempDir();
    final pubspec = temp.write('pubspec.yaml', 'name: real_app');
    final code = temp.write('lib/main.dart', 'void main() {}');
    expect(
      CorpusPackage(temp.path, 'fuzz').clean,
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('choose another --work directory'),
            contains('delete it if this'),
          ),
        ),
      ),
    );
    expect(File(pubspec).existsSync(), isTrue);
    expect(File(code).existsSync(), isTrue);
  });

  test('an empty directory and one written by the tool are cleaned', () {
    final temp = TempDir();
    CorpusPackage(temp.path, 'fuzz').clean();
    final package = CorpusPackage(temp.path, 'fuzz')
      ..write(const {}, '/runtime');
    final stale = temp.write('lib/old/api.dart', '');
    package.clean();
    expect(File(stale).existsSync(), isFalse);
  });

  test(
    'a run removes the output a reused work dir holds for other modes',
    () async {
      final temp = TempDir();
      final stale = temp.write('work/structural/lib/stale/api.dart', '');
      temp.write('work/structural/pubspec.yaml', 'name: keep');
      temp.write('work/structural/${CorpusPackage.marker}', '');
      await CorpusRun(
        work: p.join(temp.path, 'work'),
        runtime: runtimeDirectory(),
        modes: const ['raw'],
        fetchesPackages: false,
      ).run(
        [entry('pets', const Generates())],
        {
          'pets': temp.write('specs/pets.yaml', _spec),
        },
      );
      expect(File(stale).existsSync(), isFalse);
      expect(
        File(p.join(temp.path, 'work/structural/pubspec.yaml')).existsSync(),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a pub get failure reports what pub said', () async {
    final temp = TempDir();
    temp.write('pubspec.yaml', '''
name: broken
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  missing:
    path: ./does_not_exist
''');
    final failures = await PackageGate(
      temp.path,
      fetchesPackages: false,
    ).run();
    expect(failures, hasLength(1));
    expect(failures.single, contains('dart pub get failed'));
    expect(failures.single, contains('does_not_exist'));
  });
}
