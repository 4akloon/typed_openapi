import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';
import 'package:typed_openapi/src/generate/output_writer.dart';

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
  late TempDir dir;

  setUp(() {
    dir = TempDir();
    dir.write('specs/pets.yaml', _spec);
  });

  Future<(int, String)> generate(String clients) async {
    dir.write('typed_openapi.yaml', 'clients:\n$clients');
    final out = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: dir.path,
    ).run(['generate']);
    return (code, out.toString());
  }

  /// The files under [relative] with their content, by relative path.
  Map<String, String> tree(String relative) {
    final root = Directory(p.join(dir.path, relative));
    if (!root.existsSync()) return const {};
    return {
      for (final file
          in root.listSync(recursive: true).whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        p.relative(file.path, from: root.path).replaceAll(r'\', '/'): file
            .readAsStringSync(),
    };
  }

  test('writes the models and the manifest, then nothing new', () async {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
    final (code, out) = await generate(client);
    expect(code, 0);
    expect(
      out,
      endsWith(
        'Generated pets in ${p.join('gen', 'pets')}: 3 files, 3 written, '
        '0 deleted.\n',
      ),
    );
    final first = tree('gen/pets');
    expect(first.keys, [
      '.typed_openapi.json',
      'models.dart',
      'models/pet.dart',
      'models/pet_status.dart',
    ]);
    final manifest =
        jsonDecode(first['.typed_openapi.json']!) as Map<String, Object?>;
    expect(manifest['generator'], OutputWriter.generator);
    expect(manifest['inputs'], hasLength(64));
    expect((manifest['files']! as Map<String, Object?>).keys, [
      'models.dart',
      'models/pet.dart',
      'models/pet_status.dart',
    ]);
    final (again, log) = await generate(client);
    expect(again, 0);
    expect(log, contains('3 files, 0 written, 0 deleted.'));
    expect(tree('gen/pets'), first);
  });

  test('deletes what it no longer writes, empty directories too', () async {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
    await generate(client);
    dir
      ..write('gen/pets/models/old.dart', '// old')
      ..write('gen/pets/stale/deep/x.dart', '// x');
    final (code, out) = await generate(client);
    expect(code, 0);
    expect(out, contains('3 files, 0 written, 2 deleted.'));
    expect(tree('gen/pets').keys, [
      '.typed_openapi.json',
      'models.dart',
      'models/pet.dart',
      'models/pet_status.dart',
    ]);
    expect(Directory(p.join(dir.path, 'gen/pets/stale')).existsSync(), isFalse);
  });

  test('the manifest changes with the inputs', () async {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
    await generate(client);
    final before = tree('gen/pets')['.typed_openapi.json'];
    dir.write('specs/pets.yaml', '$_spec\n# a comment\n');
    await generate(client);
    expect(tree('gen/pets')['.typed_openapi.json'], isNot(before));
  });

  test('skips a client whose check reports errors', () async {
    final (code, out) = await generate(
      '  pets: {input: specs/pets.yaml, output: gen/pets, '
      'overrides: missing.yaml}\n',
    );
    expect(code, 1);
    expect(out, contains('error TOA801 overrides-not-found'));
    expect(
      out,
      endsWith(
        'Skipped pets: its check reports errors; fix them and run generate '
        'again.\n',
      ),
    );
    expect(tree('gen/pets'), isEmpty);
  });

  test('the manifest names the version of the pubspec', () {
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect(OutputWriter.generator, 'typed_openapi $version');
  });

  group('refuses an output directory it may not own (TOA830)', () {
    Future<void> refused(String output, String why) async {
      final (code, out) = await generate(
        '  pets: {input: specs/pets.yaml, output: $output}\n',
      );
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains(why));
      expect(out, contains('Skipped pets: see the error above.'));
    }

    test('a package', () async {
      dir.write('app/pubspec.yaml', 'name: app\n');
      await refused('app', 'holds a pubspec.yaml');
      expect(tree('app').keys, ['pubspec.yaml']);
    });

    test("a package's lib", () async {
      dir
        ..write('app/pubspec.yaml', 'name: app\n')
        ..write('app/lib/main.dart', '// mine');
      await refused('app/lib', 'is the lib directory of a package');
      expect(tree('app/lib').keys, ['main.dart']);
    });

    test('a directory with an input of the run', () async {
      await refused('specs', 'an input of the run');
      expect(tree('specs').keys, ['pets.yaml']);
    });

    test('a directory with files of someone else', () async {
      dir.write('gen/pets/notes.txt', 'mine');
      await refused('gen/pets', 'holds files but no .typed_openapi.json');
      expect(tree('gen/pets').keys, ['notes.txt']);
    });
  });

  group('never deletes an input of the run', () {
    const manifest = '{"generator": "typed_openapi 0.0.1", "files": {}}';

    test('reached through a symbolic link', () async {
      dir
        ..link('alias', 'specs')
        ..write('specs/.typed_openapi.json', manifest);
      final (code, out) = await generate(
        '  pets: {input: alias/pets.yaml, output: specs}\n',
      );
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains('an input of the run'));
      expect(tree('specs').keys, ['.typed_openapi.json', 'pets.yaml']);
    });

    test('named with another case', () async {
      if (!dir.isCaseInsensitive) {
        markTestSkipped('the file system is case-sensitive');
        return;
      }
      dir.write('specs/.typed_openapi.json', manifest);
      final (code, out) = await generate(
        '  pets: {input: Specs/pets.yaml, output: SPECS}\n',
      );
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(tree('specs').keys, ['.typed_openapi.json', 'pets.yaml']);
    });

    test('the config file, found through a link', () async {
      dir
        ..write('gen/.typed_openapi.json', manifest)
        ..link('alias', 'gen');
      // The config sits in the output directory.
      final out = StringBuffer();
      dir.write(
        'gen/typed_openapi.yaml',
        'clients:\n  pets: {input: ../specs/pets.yaml, output: ../gen}\n',
      );
      final code = await TypedOpenApiCli(
        out: out,
        err: out,
        workingDirectory: dir.path,
      ).run(['generate', '--config', 'alias/typed_openapi.yaml']);
      expect(code, 1);
      expect(out.toString(), contains('error TOA830 output-not-owned'));
      expect(out.toString(), contains('an input of the run'));
      expect(
        File(p.join(dir.path, 'gen/typed_openapi.yaml')).existsSync(),
        isTrue,
      );
    });
  });

  group('clients with overlapping outputs are all skipped (TOA904)', () {
    Future<void> skipped(String clients) async {
      final (code, out) = await generate(clients);
      expect(code, 1);
      expect(out, contains('error TOA904 output-overlap'));
      expect(out, contains('Skipped a: its output overlaps'));
      expect(out, contains('Skipped b: its output overlaps'));
      expect(tree('gen'), isEmpty);
    }

    test('the same directory', () async {
      await skipped(
        '  a: {input: specs/pets.yaml, output: gen/x}\n'
        '  b: {input: specs/pets.yaml, output: gen/x}\n',
      );
    });

    test('one inside the other', () async {
      await skipped(
        '  a: {input: specs/pets.yaml, output: gen/x}\n'
        '  b: {input: specs/pets.yaml, output: gen/x/y}\n',
      );
    });

    test('the same directory through a link', () async {
      Directory(p.join(dir.path, 'gen')).createSync();
      dir.link('alias', 'gen');
      await skipped(
        '  a: {input: specs/pets.yaml, output: gen/x}\n'
        '  b: {input: specs/pets.yaml, output: alias/x}\n',
      );
    });

    test('a client that does not overlap is generated', () async {
      final (code, out) = await generate(
        '  a: {input: specs/pets.yaml, output: gen/x}\n'
        '  b: {input: specs/pets.yaml, output: gen/x/y}\n'
        '  c: {input: specs/pets.yaml, output: gen/z}\n',
      );
      expect(code, 1);
      expect(out, contains('Generated c in ${p.join('gen', 'z')}'));
      expect(tree('gen/x'), isEmpty);
    });
  });

  group('an output directory that is not what it seems', () {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';

    test('a symbolic link inside is foreign (TOA830)', () async {
      await generate(client);
      dir.write('outside/keep.txt', 'mine');
      dir.link('gen/pets/models/link', 'outside');
      final before = tree('gen/pets');
      final (code, out) = await generate(client);
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains('symbolic link'));
      expect(tree('outside').keys, ['keep.txt']);
      expect(tree('gen/pets'), before);
    });

    test('an unreadable directory is TOA831, not a crash', () async {
      await generate(client);
      final output = Directory(p.join(dir.path, 'gen/pets'));
      Process.runSync('chmod', ['000', output.path]);
      addTearDown(() => Process.runSync('chmod', ['755', output.path]));
      if (Directory(output.path).statSync().mode & 0x1ff != 0) {
        markTestSkipped('permissions are not enforced here');
        return;
      }
      final (code, out) = await generate(client);
      expect(code, 1);
      expect(out, contains('error TOA831 output-not-written'));
    });

    test('a manifest that is not JSON means foreign files (TOA830)', () async {
      dir
        ..write('gen/pets/.typed_openapi.json', 'not json')
        ..write('gen/pets/notes.txt', 'mine');
      final (code, out) = await generate(client);
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains('is not a manifest of typed_openapi'));
      expect(tree('gen/pets').keys, ['.typed_openapi.json', 'notes.txt']);
    });

    test('a manifest of another generator means foreign files', () async {
      dir
        ..write('gen/pets/.typed_openapi.json', '{"generator": "other 1"}')
        ..write('gen/pets/notes.txt', 'mine');
      final (code, out) = await generate(client);
      expect(code, 1);
      expect(out, contains('is not a manifest of typed_openapi'));
      expect(tree('gen/pets').keys, ['.typed_openapi.json', 'notes.txt']);
    });

    test('a file renamed only in case is replaced, not lost', () async {
      await generate(client);
      File(
        p.join(dir.path, 'gen/pets/models/pet.dart'),
      ).renameSync(p.join(dir.path, 'gen/pets/models/Pet.dart'));
      final (code, _) = await generate(client);
      expect(code, 0);
      final names = Directory(
        p.join(dir.path, 'gen/pets/models'),
      ).listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(names, ['pet.dart', 'pet_status.dart']);
    });

    test('a second run leaves the files and the directory alone', () async {
      await generate(client);
      final output = p.join(dir.path, 'gen/pets');
      final before = [
        Directory(output).statSync().changed,
        File(p.join(output, 'models/pet.dart')).statSync().changed,
      ];
      await generate(client);
      expect([
        Directory(output).statSync().changed,
        File(p.join(output, 'models/pet.dart')).statSync().changed,
      ], before);
    });
  });
}
