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

  Future<(int, String)> generate(
    String clients, {
    List<String> args = const [],
  }) async {
    dir.write('typed_openapi.yaml', 'clients:\n$clients');
    final out = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: dir.path,
    ).run(['generate', ...args]);
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

  test('deletes the files it wrote and no longer writes', () async {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
    await generate(client);
    // The spec loses a model, so the files of the old run are stale.
    dir.write(
      'specs/pets.yaml',
      _spec.replaceAll(
        'status: {type: string, enum: [a, b]}',
        'status: {type: string}',
      ),
    );
    final (code, out) = await generate(client);
    expect(code, 0);
    expect(out, contains('2 files, 2 written, 1 deleted.'));
    expect(tree('gen/pets').keys, [
      '.typed_openapi.json',
      'models.dart',
      'models/pet.dart',
    ]);
  });

  test('empty directories are no obstacle and go with the old tree', () async {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
    await generate(client);
    Directory(
      p.join(dir.path, 'gen/pets/stale/deep'),
    ).createSync(recursive: true);
    final (code, out) = await generate(client);
    expect(code, 0);
    expect(out, contains('3 files, 0 written, 0 deleted.'));
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

  group('deletes only what it wrote and finds unchanged (TOA830)', () {
    const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';

    /// Runs `generate` for [client]; the output must have been refused with
    /// a message that names [names], and [kept] must be as it was.
    Future<void> refused(
      List<String> names, {
      List<String> args = const [],
      Map<String, String> kept = const {},
    }) async {
      final (code, out) = await generate(client, args: args);
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      for (final name in names) {
        expect(out, contains(name));
      }
      expect(out, contains('--force'));
      expect(out, contains('Skipped pets: see the error above.'));
      for (final MapEntry(:key, :value) in kept.entries) {
        expect(File(p.join(dir.path, key)).readAsStringSync(), value);
      }
    }

    test('a file of the user dropped into the output', () async {
      await generate(client);
      dir.write('gen/pets/notes.txt', 'mine');
      final before = tree('gen/pets');
      await refused(['notes.txt', 'not written by typed_openapi']);
      expect(tree('gen/pets'), before);
    });

    test('a file in a directory of the output', () async {
      await generate(client);
      dir.write('gen/pets/models/mine/extra.dart', '// mine');
      final before = tree('gen/pets');
      await refused([p.posix.join('models', 'mine', 'extra.dart')]);
      expect(tree('gen/pets'), before);
    });

    test('a generated file that was edited by hand', () async {
      await generate(client);
      dir.write('gen/pets/models/pet.dart', '// my change\n');
      final before = tree('gen/pets');
      await refused(['models/pet.dart', 'changed since']);
      expect(tree('gen/pets'), before);
    });

    test(
      'a file whose content is what the run writes is no obstacle',
      () async {
        // An edit that was undone, and a manifest that lost the hash.
        await generate(client);
        const path = 'gen/pets/.typed_openapi.json';
        final manifest =
            jsonDecode(File(p.join(dir.path, path)).readAsStringSync())
                as Map<String, Object?>;
        manifest['files'] = [
          ...(manifest['files']! as Map<String, Object?>).keys,
        ];
        dir.write(path, jsonEncode(manifest));
        final (code, out) = await generate(client);
        expect(code, 0);
        expect(out, isNot(contains('TOA830')));
      },
    );

    test('a manifest without the hashes of its files, written by an older '
        'typed_openapi, counts them as modified', () async {
      await generate(client);
      const path = 'gen/pets/.typed_openapi.json';
      final manifest =
          jsonDecode(File(p.join(dir.path, path)).readAsStringSync())
              as Map<String, Object?>;
      manifest
        ..remove('format')
        ..['files'] = [...(manifest['files']! as Map<String, Object?>).keys];
      dir.write(path, jsonEncode(manifest));
      // The spec changes, so the files would be different.
      dir.write('specs/pets.yaml', _spec.replaceAll('[a, b]', '[a, b, c]'));
      final before = tree('gen/pets');
      await refused(
        ['models/pet_status.dart', 'no hash', 'older typed_openapi'],
      );
      expect(tree('gen/pets'), before);
      final (code, out) = await generate(client, args: ['--force']);
      expect(code, 0);
      expect(out, contains('Generated pets in'));
      final manifestNow =
          jsonDecode(tree('gen/pets')['.typed_openapi.json']!)
              as Map<String, Object?>;
      expect(manifestNow['format'], OutputWriter.manifestFormat);
      expect(manifestNow['files'], isA<Map<String, Object?>>());
      // Hashes are there now: no --force needed.
      final (again, _) = await generate(client);
      expect(again, 0);
    });

    test('--force replaces foreign and modified files', () async {
      await generate(client);
      dir
        ..write('gen/pets/notes.txt', 'mine')
        ..write('gen/pets/models/pet.dart', '// my change\n');
      final (code, out) = await generate(client, args: ['--force']);
      expect(code, 0);
      expect(out, isNot(contains('TOA830')));
      expect(out, contains('Generated pets in'));
      expect(out, contains('--force replaced 2'));
      expect(tree('gen/pets').keys, [
        '.typed_openapi.json',
        'models.dart',
        'models/pet.dart',
        'models/pet_status.dart',
      ]);
      expect(tree('gen/pets')['models/pet.dart'], isNot('// my change\n'));
    });

    test('--force on a clean output says nothing about replacing', () async {
      await generate(client);
      final before = tree('gen/pets');
      final (code, out) = await generate(client, args: ['--force']);
      expect(code, 0);
      expect(out, isNot(contains('replaced')));
      expect(out, contains('3 files, 0 written, 0 deleted.'));
      expect(tree('gen/pets'), before);
    });

    test('--force takes a directory that has files but no manifest', () async {
      dir.write('gen/pets/notes.txt', 'mine');
      await refused(['notes.txt', 'no .typed_openapi.json']);
      final (code, _) = await generate(client, args: ['--force']);
      expect(code, 0);
      expect(tree('gen/pets').keys, contains('models.dart'));
      expect(tree('gen/pets').keys, isNot(contains('notes.txt')));
    });

    test('--force never takes a package, a link or an input', () async {
      dir.write('app/pubspec.yaml', 'name: app\n');
      final (code, out) = await generate(
        '  pets: {input: specs/pets.yaml, output: app}\n',
        args: ['--force'],
      );
      expect(code, 1);
      expect(out, contains('holds a pubspec.yaml'));
      expect(tree('app').keys, ['pubspec.yaml']);
      final (code2, out2) = await generate(
        '  pets: {input: specs/pets.yaml, output: specs}\n',
        args: ['--force'],
      );
      expect(code2, 1);
      expect(out2, contains('an input of the run'));
      expect(tree('specs').keys, ['pets.yaml']);
    });

    group("a file another client reads, in this client's output", () {
      const pair =
          '  a: {input: specs/pets.yaml, output: gen/a}\n'
          '  b: {input: specs/b.yaml, output: gen/b}\n';

      /// Generates a, drops `gen/a/shared.yaml` and runs [args].
      Future<String> run(
        String shared, {
        String b = 'specs/b.yaml',
        String bText = '',
        List<String> args = const [],
      }) async {
        dir.write(
          'specs/b.yaml',
          bText.isEmpty
              ? _spec.replaceAll(
                  "'#/components/schemas/Pet'",
                  "'../gen/a/shared.yaml#/Owner'",
                )
              : bText,
        );
        await generate(pair);
        dir.write('gen/a/shared.yaml', shared);
        final (_, out) = await generate(pair, args: args);
        return out;
      }

      const owner = 'Owner: {type: object, properties: {id: {type: string}}}\n';

      test('only a is run, and b is not even checked', () async {
        dir.write('specs/b.yaml', _spec);
        await generate(pair);
        dir.write('gen/a/shared.yaml', owner);
        final out = StringBuffer();
        final code = await TypedOpenApiCli(
          out: out,
          err: out,
          workingDirectory: dir.path,
        ).run(['generate', 'a']);
        expect(code, 1);
        expect(out.toString(), contains('error TOA830 output-not-owned'));
        expect(out.toString(), contains('shared.yaml'));
        expect(
          File(p.join(dir.path, 'gen/a/shared.yaml')).existsSync(),
          isTrue,
        );
      });

      test('the file has a YAML syntax error', () async {
        final out = await run('Owner: {type: object\n');
        expect(out, contains('TOA830'));
        expect(out, contains('shared.yaml'));
        expect(
          File(p.join(dir.path, 'gen/a/shared.yaml')).readAsStringSync(),
          'Owner: {type: object\n',
        );
      });

      test('the root spec of b has a syntax error', () async {
        final out = await run(
          owner,
          bText: 'openapi: 3.1.0\ninfo: {title: t\n',
        );
        expect(out, contains('TOA830'));
        expect(out, contains('shared.yaml'));
        expect(
          File(p.join(dir.path, 'gen/a/shared.yaml')).readAsStringSync(),
          owner,
        );
      });

      test('--force keeps it while another client can read it', () async {
        final out = await run(owner, args: ['--force']);
        expect(out, contains('an input of the run'));
        expect(out, contains('Skipped a:'));
        expect(
          File(p.join(dir.path, 'gen/a/shared.yaml')).existsSync(),
          isTrue,
        );
      });

      test('--force replaces it when no client could read it', () async {
        final out = await run(
          owner,
          bText: 'openapi: 3.1.0\ninfo: {title: t\n',
          args: ['--force'],
        );
        expect(out, contains('Generated a in'));
        expect(out, contains('--force replaced 1'));
        expect(
          File(p.join(dir.path, 'gen/a/shared.yaml')).existsSync(),
          isFalse,
        );
      });
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

    test("another client's spec in this client's output", () async {
      dir
        ..write('bspecs/.typed_openapi.json', manifest)
        ..write('bspecs/pets.yaml', _spec);
      final (code, out) = await generate(
        '  a: {input: specs/pets.yaml, output: bspecs}\n'
        '  b: {input: bspecs/pets.yaml, output: gen/b}\n',
      );
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains('Skipped a: see the error above.'));
      expect(out, contains('Generated b in'));
      expect(tree('bspecs').keys, ['.typed_openapi.json', 'pets.yaml']);
    });

    test("another client's overrides file in this client's output", () async {
      dir
        ..write('gen2/.typed_openapi.json', manifest)
        ..write('gen2/ov.yaml', 'schemas: {}\n');
      final (code, out) = await generate(
        '  a: {input: specs/pets.yaml, output: gen2}\n'
        '  b: {input: specs/pets.yaml, output: gen/b, overrides: gen2/ov.yaml}\n',
      );
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(tree('gen2').keys, ['.typed_openapi.json', 'ov.yaml']);
    });

    test('a client that is not selected is protected too', () async {
      dir
        ..write('bspecs/.typed_openapi.json', manifest)
        ..write('bspecs/pets.yaml', _spec);
      dir.write(
        'typed_openapi.yaml',
        'clients:\n'
            '  a: {input: specs/pets.yaml, output: bspecs}\n'
            '  b: {input: bspecs/pets.yaml, output: gen/b, baseline: bspecs/base.yaml}\n',
      );
      final out = StringBuffer();
      final code = await TypedOpenApiCli(
        out: out,
        err: out,
        workingDirectory: dir.path,
      ).run(['generate', 'a']);
      expect(code, 1);
      expect(out.toString(), contains('error TOA830 output-not-owned'));
      expect(tree('bspecs').keys, ['.typed_openapi.json', 'pets.yaml']);
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

    test('a generated file renamed only in case is foreign (TOA830)', () async {
      await generate(client);
      File(
        p.join(dir.path, 'gen/pets/models/pet.dart'),
      ).renameSync(p.join(dir.path, 'gen/pets/models/Pet.dart'));
      final (code, out) = await generate(client);
      expect(code, 1);
      expect(out, contains('error TOA830 output-not-owned'));
      expect(out, contains('Pet.dart'));
      final (forced, _) = await generate(client, args: ['--force']);
      expect(forced, 0);
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
