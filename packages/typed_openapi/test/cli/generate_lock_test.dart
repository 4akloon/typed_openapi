@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
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
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''';

const _pets = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
const _other = '  other: {input: specs/pets.yaml, output: gen/other}\n';
const _same =
    'API of pets since typed_openapi.lock: 0 breaking, 0 switch-breaking, '
    '0 wire, 0 additive, 0 docs.';

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

  File lockFile() => File(p.join(dir.path, 'typed_openapi.lock'));

  /// Adds the enum value `c` to the spec: a switch-breaking change.
  void addValue() =>
      dir.write('specs/pets.yaml', _spec.replaceFirst('[a, b]', '[a, b, c]'));

  test(
    'the first run writes the snapshot of each client to the lock',
    () async {
      final (code, out) = await generate(_pets);
      expect(code, 0);
      expect(
        out,
        contains('API of pets: first snapshot in typed_openapi.lock.'),
      );
      final lock = const SnapshotJson().decode(lockFile().readAsStringSync());
      expect(lock.keys, ['pets']);
      expect(lock['pets']!.types['#/components/schemas/Pet']!.name, 'Pet');
    },
  );

  test('a run without changes counts none and keeps the lock', () async {
    await generate(_pets);
    final before = lockFile().readAsStringSync();
    final (_, out) = await generate(_pets);
    expect(out, contains(_same));
    expect(lockFile().readAsStringSync(), before);
  });

  test('a run counts the changes by category and records them', () async {
    await generate(_pets);
    addValue();
    final (code, out) = await generate(_pets);
    expect(code, 0);
    expect(out, contains('0 breaking, 1 switch-breaking, 0 wire'));
    expect(lockFile().readAsStringSync(), contains(r'"\"c\""'));
  });

  test('a run of one client keeps the snapshot of another', () async {
    await generate(_pets + _other);
    await generate(_pets + _other, args: ['pets']);
    final lock = const SnapshotJson().decode(lockFile().readAsStringSync());
    expect(lock.keys, ['other', 'pets']);
  });

  test('the snapshot of a client the config dropped is removed', () async {
    await generate(_pets + _other);
    await generate(_pets);
    final lock = const SnapshotJson().decode(lockFile().readAsStringSync());
    expect(lock.keys, ['pets']);
  });

  group('--locked', () {
    test('passes when the API is the one in the lock', () async {
      await generate(_pets);
      final before = lockFile().readAsStringSync();
      final (code, out) = await generate(_pets, args: ['--locked']);
      expect(code, 0);
      expect(out, contains(_same));
      expect(lockFile().readAsStringSync(), before);
    });

    test(
      'fails on a changed API and writes neither the client nor the lock',
      () async {
        await generate(_pets);
        final before = lockFile().readAsStringSync();
        addValue();
        final (code, out) = await generate(_pets, args: ['--locked']);
        expect(code, 1);
        expect(out, contains('TOA834'));
        expect(out, contains('0 breaking, 1 switch-breaking'));
        expect(out, contains('Skipped pets: its API differs from'));
        expect(lockFile().readAsStringSync(), before);
        expect(
          File(
            p.join(dir.path, 'gen/pets/models/pet_status.dart'),
          ).readAsStringSync(),
          isNot(contains("'c'")),
        );
      },
    );

    test('fails without a lock and creates none', () async {
      final (code, out) = await generate(_pets, args: ['--locked']);
      expect(code, 1);
      expect(out, contains('has no snapshot of client "pets"'));
      expect(lockFile().existsSync(), isFalse);
    });

    test('fails on the snapshot of a client the config dropped', () async {
      await generate(_pets + _other);
      final (code, out) = await generate(_pets, args: ['--locked']);
      expect(code, 1);
      expect(out, contains('client "other", which the config no longer'));
    });
  });

  group('names', () {
    /// Adds a component `PetStatus` that `Pet` uses: without the lock it
    /// would take the name of the enum of `Pet.status`.
    void addSchema() => dir.write(
      'specs/pets.yaml',
      '$_spec'
          r"        detail: {$ref: '#/components/schemas/PetStatus'}"
          '\n    PetStatus: {type: object, properties: {code: {}}}\n',
    );

    test('a new schema renames no type of the lock', () async {
      await generate(_pets);
      addSchema();
      final (code, out) = await generate(_pets);
      expect(code, 0);
      expect(out, contains(': 0 breaking, 0 switch-breaking, 0 wire, 2 '));
      expect(
        File(
          p.join(dir.path, 'gen/pets/models/pet_status_2.dart'),
        ).readAsStringSync(),
        contains('class PetStatus2 {'),
      );
    });

    test('--fresh-names names the types anew', () async {
      await generate(_pets);
      addSchema();
      final (code, out) = await generate(_pets, args: ['--fresh-names']);
      expect(code, 0);
      expect(
        out,
        contains(
          'API of pets since typed_openapi.lock: 4 breaking, 0 switch-breaking, '
          '0 wire, 2 additive, 0 docs.',
        ),
      );
    });
  });

  test('a lock that is not a lock stops the run and is kept', () async {
    lockFile().writeAsStringSync('<<<<<<< HEAD\n');
    final (code, out) = await generate(_pets);
    expect(code, 1);
    expect(out, contains('TOA835'));
    expect(out, contains('Skipped every client'));
    expect(lockFile().readAsStringSync(), '<<<<<<< HEAD\n');
    expect(Directory(p.join(dir.path, 'gen')).existsSync(), isFalse);
  });
}
