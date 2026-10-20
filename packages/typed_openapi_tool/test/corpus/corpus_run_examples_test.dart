@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_run.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';

import '../helpers/corpus_entry.dart';

const _spec = r'''
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
              schema: {$ref: "#/components/schemas/Pet"}
components:
  schemas:
    Pet:
      type: object
      properties:
        weight: {type: number}
      examples:
        - {weight: .nan}
        - {weight: .inf}
        - {weight: 2.5}
      example: null
''';

void main() {
  test('an example JSON cannot write is a spec defect, not a crash', () async {
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
    expect(result.roundTrips, isEmpty);
    expect(result.lock.clients['raw/pets']!.values, {
      'examples': 1,
      'examples_skipped': 1,
      'failures': 0,
      'spec_defects': 2,
      'synthetic': 2,
      'synthetic_skipped': 0,
    });
    expect(result.defects, hasLength(2));
    expect(result.defects.first, startsWith('raw/pets: Pet: an example'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a round trip that did not run is a failure of the run', () async {
    final temp = TempDir();
    final result =
        await CorpusRun(
          work: p.join(temp.path, 'work'),
          runtime: runtimeDirectory(),
          modes: const ['raw'],
          fetchesPackages: false,
          roundTripTimeout: const Duration(milliseconds: 1),
        ).run(
          [entry('pets', const Generates())],
          {
            'pets': temp.write('specs/pets.yaml', _spec),
          },
        );
    expect(
      result.failures.single,
      startsWith('raw/pets: the round trip did not run'),
    );
    expect(result.roundTrips, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
