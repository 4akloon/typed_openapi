@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_run.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/generate_run.dart';

import '../helpers/corpus_entry.dart';

const _spec = '''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        "200": {description: ok}
  /broken:
    get:
      operationId: broken
      responses:
        "400": {description: bad}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''';

void main() {
  test('a config that cannot be loaded is a CorpusException', () {
    final temp = TempDir();
    final run = GenerateRun(p.join(temp.path, 'missing.yaml'));
    expect(run.check, throwsA(isA<CorpusException>()));
  });

  test('a config with an error is a CorpusException', () {
    final temp = TempDir();
    final config = temp.write('typed_openapi.yaml', 'clients: 5\n');
    expect(
      GenerateRun(config).check,
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          contains(config),
        ),
      ),
    );
  });

  test('a spec that is neither generated nor checked is a failure', () async {
    final temp = TempDir();
    final result =
        await CorpusRun(
          work: p.join(temp.path, 'work'),
          runtime: runtimeDirectory(),
          modes: const ['raw'],
          fetchesPackages: false,
        ).run(
          [entry('pets', const Generates()), entry('ghost', const Generates())],
          {
            'pets': temp.write('specs/pets.yaml', _spec),
          },
        );
    expect(result.failures, hasLength(1));
    expect(
      result.failures.single,
      startsWith('raw/ghost: expected to generate'),
    );
    expect(result.failures.single, isNot(contains('[]')));
    expect(result.lock.clients['raw/ghost']!.files, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the lock counts the diagnostics of a generated client', () async {
    final temp = TempDir();
    final result =
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
    expect(result.failures, isEmpty);
    expect(result.lock.clients['raw/pets']!.files, isNotEmpty);
    expect(
      result.lock.clients['raw/pets']!.diagnostics,
      containsPair('TOA653', 1),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
