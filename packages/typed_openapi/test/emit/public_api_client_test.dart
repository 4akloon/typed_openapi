import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/typed_openapi.dart';

import '../helpers/temp_dir.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet'}
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''';

void main() {
  test('the public library writes the same client as generate', () async {
    final dir = TempDir()
      ..write('specs/pets.yaml', _spec)
      ..write(
        'typed_openapi.yaml',
        'clients:\n  pets:\n    input: specs/pets.yaml\n    output: out\n',
      );
    final generated = await TypedOpenApiCli(
      out: StringBuffer(),
      err: StringBuffer(),
      workingDirectory: dir.path,
    ).run(['generate']);
    expect(generated, 0);

    final diagnostics = DiagnosticBag();
    final config = ConfigLoader(
      diagnostics,
    ).load(p.join(dir.path, 'typed_openapi.yaml'))!;
    final check = SpecChecker(diagnostics).check(config).single;
    final files = const ApiLibrary().files(check.ir!, client: 'pets');

    final output = Directory(p.join(dir.path, 'out'));
    final written = {
      for (final file in output.listSync(recursive: true).whereType<File>())
        p.posix.joinAll(p.split(p.relative(file.path, from: output.path))): file
            .readAsStringSync(),
    }..remove('.typed_openapi.json');
    expect(files.keys, written.keys.toList()..sort());
    expect(files['pets.dart'], written['pets.dart']);
    expect(files, written);
  });
}
