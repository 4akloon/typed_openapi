import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

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
  /owners:
    get:
      operationId: listOwners
      responses:
        '200': {description: ok}
components:
  schemas:
    Pet:
      type: object
      description: A pet.
      properties:
        name: {type: string, description: The name., maxLength: 10, default: rex}
    Unused:
      type: object
      properties:
        a: {type: string}
''';

const _include = 'include: {paths: ["/pets"]}';

void main() {
  late TempDir dir;

  setUp(() {
    dir = TempDir();
    dir.write('specs/api.yaml', _spec);
  });

  Future<int> generate({String extra = '', String filter = _include}) async {
    dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: specs/api.yaml, output: gen/api, '
          '$filter$extra}\n',
    );
    final out = StringBuffer();
    return TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: dir.path,
    ).run(['generate']);
  }

  String manifest() =>
      File(p.join(dir.path, 'gen/api/.typed_openapi.json')).readAsStringSync();

  String inputs() => (jsonDecode(manifest()) as Map)['inputs'] as String;

  Future<String> manifestAfter(String spec, {String extra = ''}) async {
    dir.write('specs/api.yaml', spec);
    expect(await generate(extra: extra), 0);
    return manifest();
  }

  Future<String> inputsAfter(String spec) async {
    await manifestAfter(spec);
    return inputs();
  }

  test('a comment does not change the manifest', () async {
    final before = await manifestAfter(_spec);
    expect(await manifestAfter('$_spec\n# a comment\n'), before);
  });

  test('a component no operation reaches does not change it', () async {
    final before = await manifestAfter(_spec);
    final changed = _spec.replaceAll(
      'a: {type: string}',
      'a: {type: integer}\n        b: {type: string}',
    );
    expect(await manifestAfter(changed), before);
  });

  test(
    'an operation the include filter leaves out does not change it',
    () async {
      final before = await manifestAfter(_spec);
      final changed = _spec.replaceAll(
        'operationId: listOwners',
        'operationId: listOwners\n      description: Changed.',
      );
      expect(await manifestAfter(changed), before);
    },
  );

  test('a description of an included operation changes it', () async {
    final before = await inputsAfter(_spec);
    final changed = _spec.replaceAll(
      'operationId: listPets',
      'operationId: listPets\n      description: Lists the pets.',
    );
    expect(await inputsAfter(changed), isNot(before));
  });

  test('a new parameter of an included operation changes it', () async {
    final before = await inputsAfter(_spec);
    final changed = _spec.replaceAll(
      'operationId: listPets',
      'operationId: listPets\n      parameters:\n'
          '        - {name: limit, in: query, schema: {type: integer}}',
    );
    expect(await inputsAfter(changed), isNot(before));
  });

  test('the line width changes it', () async {
    expect(await generate(), 0);
    final before = inputs();
    expect(await generate(extra: ', line_width: 100'), 0);
    expect(inputs(), isNot(before));
  });

  test('a second run writes nothing', () async {
    expect(await generate(), 0);
    final before = manifest();
    final stamp = File(
      p.join(dir.path, 'gen/api/.typed_openapi.json'),
    ).lastModifiedSync();
    expect(await generate(), 0);
    expect(manifest(), before);
    expect(
      File(p.join(dir.path, 'gen/api/.typed_openapi.json')).lastModifiedSync(),
      stamp,
    );
  });

  Future<void> expectChanged(String from, String to) async {
    final before = await inputsAfter(_spec);
    expect(await inputsAfter(_spec.replaceAll(from, to)), isNot(before));
  }

  test('a description of a property changes it', () async {
    await expectChanged('The name.', 'The pet name.');
  });

  test('a description of a schema changes it', () async {
    await expectChanged('A pet.', 'Any pet.');
  });

  test('a constraint of a property changes it', () async {
    await expectChanged('maxLength: 10', 'maxLength: 20');
  });

  test('a default of a property changes it', () async {
    await expectChanged('default: rex', 'default: max');
  });

  test('the working directory of the run does not change it', () async {
    expect(await generate(), 0);
    final before = manifest();
    final elsewhere = Directory(p.join(dir.path, 'sub'))..createSync();
    dir.write('gen2/.keep', '');
    final out = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: elsewhere.path,
    ).run(['generate', '-c', p.join(dir.path, 'typed_openapi.yaml')]);
    expect(code, 0, reason: '$out');
    expect(manifest(), before);
  });
}
