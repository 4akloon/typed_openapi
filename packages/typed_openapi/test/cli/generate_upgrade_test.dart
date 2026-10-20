import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

String _spec({bool withOwners = true}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {\$ref: '#/components/schemas/Pet'}}}}
${withOwners ? '''
  /owners:
    get:
      operationId: listOwners
      tags: [owners]
      responses:
        "204": {description: ok}
''' : ''}components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
''';

void main() {
  late TempDir dir;

  setUp(() {
    dir = TempDir();
    dir.write('specs/pets.yaml', _spec());
  });

  Future<(int, String)> generate([List<String> args = const []]) async {
    dir.write(
      'typed_openapi.yaml',
      'clients:\n  pets: {input: specs/pets.yaml, output: gen/pets}\n',
    );
    final out = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: dir.path,
    ).run(['generate', ...args]);
    return (code, out.toString());
  }

  String path(String relative) => p.join(dir.path, 'gen', 'pets', relative);

  test('an output with only models and a format 2 manifest upgrades', () async {
    expect((await generate()).$1, 0);
    // What the models-only generator left: the models and a manifest that
    // lists only them (the hashes are the ones of the files).
    final manifestFile = File(path('.typed_openapi.json'));
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final files = manifest['files']! as Map<String, Object?>
      ..removeWhere((name, _) => !name.startsWith('models'));
    manifest['files'] = files;
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    for (final name in ['api.dart', 'pets.dart']) {
      File(path(name)).deleteSync();
    }
    Directory(path('api')).deleteSync(recursive: true);

    final (code, out) = await generate();
    expect(code, 0, reason: out);
    expect(out, isNot(contains('TOA830')));
    expect(out, isNot(contains('TOA833')));
    expect(out, contains('0 deleted'));
    expect(File(path('api.dart')).existsSync(), isTrue);
    expect(File(path('api/pets_api.dart')).existsSync(), isTrue);
    expect(File(path('pets.dart')).existsSync(), isTrue);
    expect(File(path('models/pet.dart')).existsSync(), isTrue);
    final upgraded =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      (upgraded['files']! as Map<String, Object?>).keys,
      containsAll(['api.dart', 'api/pets_api.dart', 'pets.dart']),
    );
  });

  test('a hand-written file the full client now uses is refused', () async {
    expect((await generate()).$1, 0);
    File(path('pets.dart')).deleteSync();
    File(path('api.dart')).deleteSync();
    dir.write('gen/pets/api.dart', '// mine\n');
    final manifestFile = File(path('.typed_openapi.json'));
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    (manifest['files']! as Map<String, Object?>).removeWhere(
      (name, _) => !name.startsWith('models'),
    );
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    final (code, out) = await generate();
    expect(code, 1);
    expect(out, contains('TOA830'));
    expect(File(path('api.dart')).readAsStringSync(), '// mine\n');
  });

  test('removing an operation deletes the file of its group', () async {
    expect((await generate()).$1, 0);
    expect(File(path('api/owners_api.dart')).existsSync(), isTrue);
    expect(
      File(path('api.dart')).readAsStringSync(),
      contains("export 'api/owners_api.dart';"),
    );
    dir.write('specs/pets.yaml', _spec(withOwners: false));
    final (code, out) = await generate();
    expect(code, 0, reason: out);
    expect(out, contains('1 deleted'));
    expect(File(path('api/owners_api.dart')).existsSync(), isFalse);
    expect(File(path('api/pets_api.dart')).existsSync(), isTrue);
    expect(
      File(path('api.dart')).readAsStringSync(),
      isNot(contains('owners_api')),
    );
  });
}
