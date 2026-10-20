@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_run.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';

import '../helpers/corpus_entry.dart';

const _pets = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {type: array, items: {$ref: "#/components/schemas/Pet"}}
components:
  schemas:
    Pet:
      type: object
      required: [id]
      properties: {id: {type: string}}
      example: {id: 1}
      examples: [{id: a}]
''';

const _broken = '''
openapi: 3.1.0
info: {title: Broken, version: "1"}
paths: {}
components:
  schemas:
    When: {type: string, example: !!timestamp 2001-12-14}
''';

void main() {
  test('generates, locks and checks each expectation', () async {
    final temp = TempDir();
    final inputs = {
      'pets': temp.write('specs/pets.yaml', _pets),
      'broken': temp.write('specs/broken.yaml', _broken),
      'also_broken': temp.write('specs/also.yaml', _broken),
    };
    final result =
        await CorpusRun(
          work: p.join(temp.path, 'work'),
          runtime: runtimeDirectory(),
          modes: const ['raw'],
          fetchesPackages: false,
        ).run([
          entry('pets', const Generates()),
          entry('broken', const CheckErrors(['TOA009'])),
          entry('also_broken', const Generates()),
        ], inputs);
    expect(result.failures, [
      'raw/also_broken: expected to generate, but it was skipped for '
          '[TOA009].',
    ]);
    final pets = result.lock.clients['raw/pets']!;
    expect(pets.files.keys, containsAll(['api.dart', 'models/pet.dart']));
    expect(pets.files.keys, isNot(contains(CorpusRun.manifest)));
    expect(pets.values, {
      'examples': 1,
      'examples_skipped': 0,
      'failures': 0,
      'spec_defects': 1,
      'synthetic': 2,
      'synthetic_skipped': 0,
    });
    expect(result.lock.clients['raw/broken']!.files, isEmpty);
    expect(result.lock.clients['raw/broken']!.values, isNull);
    expect(result.lock.clients['raw/broken']!.diagnostics['TOA009'], 1);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
