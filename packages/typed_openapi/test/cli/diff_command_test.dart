@TestOn('vm')
library;

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
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''';

const _config =
    'clients:\n  pets: {input: specs/pets.yaml, output: gen/pets}\n';

void main() {
  late TempDir dir;

  setUp(() {
    dir = TempDir();
    dir.write('specs/pets.yaml', _spec);
    dir.write('typed_openapi.yaml', _config);
  });

  Future<(int, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: err,
      workingDirectory: dir.path,
    ).run(args);
    return (code, out.toString(), err.toString());
  }

  String lock() =>
      File(p.join(dir.path, 'typed_openapi.lock')).readAsStringSync();

  /// Generates, then changes the spec by [change].
  Future<void> generateThen(String Function(String) change) async {
    await run(['generate']);
    dir.write('specs/pets.yaml', change(_spec));
  }

  String addValue(String spec) => spec.replaceFirst('[a, b]', '[a, b, c]');

  test('reports no change right after generate', () async {
    await run(['generate']);
    final (code, out, _) = await run(['diff']);
    expect(code, 0);
    expect(out, 'pets: no changes.\n');
  });

  test('reports a change by category and writes nothing', () async {
    await generateThen(addValue);
    final before = lock();
    final (code, out, _) = await run(['diff']);
    expect(code, 0);
    expect(
      out,
      'pets: 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs.\n'
      '  switch-breaking: Enum value PetStatus.c was added.\n',
    );
    expect(lock(), before);
  });

  for (final (failOn, code) in [
    ('breaking', 0),
    ('switch-breaking', 1),
    ('wire', 1),
    ('any', 1),
  ]) {
    test('--fail-on $failOn exits $code on a switch-breaking change', () async {
      await generateThen(addValue);
      expect((await run(['diff', '--fail-on', failOn])).$1, code);
    });
  }

  test('--fail-on any fails on an additive change, wire does not', () async {
    await generateThen(
      (s) => s.replaceFirst(
        'properties:\n',
        'properties:\n        name: {type: string}\n',
      ),
    );
    expect((await run(['diff', '--fail-on', 'wire'])).$1, 0);
    expect((await run(['diff', '--fail-on', 'any'])).$1, 1);
  });

  test(
    'a renamed schema comes with the override that keeps its name',
    () async {
      await generateThen((s) => s.replaceAll('Pet', 'Animal'));
      final (_, out, _) = await run(['diff']);
      expect(
        out,
        contains(
          '  breaking: Model Pet was removed.\n'
          '    Keep the old name with this override:\n'
          '      schemas:\n'
          '        Animal:\n'
          '          name: Pet\n',
        ),
      );
    },
  );

  test('without a lock every type is new', () async {
    final (code, out, _) = await run(['diff']);
    expect(code, 0);
    expect(out, startsWith('pets: 0 breaking, 0 switch-breaking, 0 wire, '));
    expect(out, contains('additive: Model Pet was added.'));
  });

  test('--format json counts and lists the changes', () async {
    await generateThen(addValue);
    final (_, out, _) = await run(['diff', '--format', 'json']);
    final json = jsonDecode(out) as Map<String, Object?>;
    final pets = (json['clients']! as Map<String, Object?>)['pets']!;
    expect((pets as Map<String, Object?>)['counts'], {
      'breaking': 0,
      'switch-breaking': 1,
      'wire': 0,
      'additive': 0,
      'docs': 0,
    });
    expect(pets['changes'], hasLength(1));
  });

  test('--format markdown writes a comment', () async {
    await generateThen(addValue);
    final (_, out, _) = await run(['diff', '--format', 'markdown']);
    expect(out, startsWith('## API changes\n\n### pets: 0 breaking'));
    expect(out, contains('- Enum value PetStatus.c was added.\n'));
  });

  test('--from and --to compare two lock files without a config', () async {
    await run(['generate']);
    File(
      p.join(dir.path, 'typed_openapi.lock'),
    ).copySync(p.join(dir.path, 'old.lock'));
    dir.write('specs/pets.yaml', addValue(_spec));
    await run(['generate']);
    File(p.join(dir.path, 'typed_openapi.yaml')).deleteSync();
    final (code, out, _) = await run([
      'diff',
      '--from',
      'old.lock',
      '--to',
      'typed_openapi.lock',
    ]);
    expect(code, 0);
    expect(out, contains('1 switch-breaking'));
  });

  test('--to without --from is a usage error', () async {
    expect((await run(['diff', '--to', 'typed_openapi.lock'])).$1, 64);
  });

  test('an unknown client is a usage error', () async {
    expect((await run(['diff', 'nope'])).$1, 64);
  });

  test('a lock that cannot be read fails with TOA835 on stderr', () async {
    dir.write('typed_openapi.lock', '{');
    final (code, out, err) = await run(['diff']);
    expect(code, 1);
    expect(out, isEmpty);
    expect(err, contains('TOA835'));
  });
}
