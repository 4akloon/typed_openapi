@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/roundtrip/example_reader.dart';
import 'package:typed_openapi_tool/src/roundtrip/round_trip.dart';
import 'package:typed_openapi_tool/src/roundtrip/roundtrip_program.dart';

import '../helpers/client_ir.dart';
import '../helpers/temp_dir.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: getPet
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Pet"}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''';

void main() {
  test(
    'a program that outlives the timeout did not run, nothing else',
    () async {
      final result = await RoundTrip(
        TempDir().path,
        'corpus_raw',
        timeout: const Duration(milliseconds: 1),
      ).run('api', clientIr(_spec), ExampleReader());
      expect(result.notRun.single, contains('the round trip did not run'));
      expect(result.notRun.single, contains('was killed'));
      expect(result.failures, isEmpty);
      expect(result.examples, 0);
    },
  );

  test('a program that crashes did not run either', () async {
    final result = await RoundTrip(
      TempDir().path,
      'corpus_raw',
    ).run('api', clientIr(_spec), ExampleReader());
    expect(result.notRun.single, contains('the round trip did not run'));
    expect(result.failures, isEmpty);
  });

  test('a class name is escaped in the string that keys its codec', () {
    expect(RoundTripProgram.literal(r"a$b'c\d"), r"a\$b\'c\\d");
    expect(RoundTripProgram.literal('Pet'), 'Pet');
  });
}
