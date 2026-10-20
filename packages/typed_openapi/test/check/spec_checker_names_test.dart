@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/cli/cli.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/name_lock.dart';

import '../helpers/temp_dir.dart';

const _spec = r'''
openapi: 3.0.3
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

const _inline = '#/components/schemas/Pet/properties/status';

String _typeAt(ClientIr ir, String pointer) => ir.declarations
    .firstWhere((d) => d.id.location.pointer.value == pointer)
    .name;

void main() {
  late TempDir dir;

  /// Generates [clients] with a lock written for the spec before it got
  /// a component `PetStatus`, then adds the component.
  Future<void> lockThenAddSchema(String clients) async {
    dir = TempDir()
      ..write('specs/pets.yaml', _spec)
      ..write(
        'typed_openapi.yaml',
        'clients:\n  pets: {input: specs/pets.yaml, output: gen/pets}\n',
      );
    final out = StringBuffer();
    await TypedOpenApiCli(
      out: out,
      err: out,
      workingDirectory: dir.path,
    ).run(['generate']);
    dir
      ..write(
        'specs/pets.yaml',
        '$_spec        detail: {\$ref: \'#/components/schemas/PetStatus\'}\n'
            '    PetStatus: {type: object, properties: {code: {}}}\n',
      )
      ..write('typed_openapi.yaml', 'clients:\n$clients');
  }

  List<ClientCheck> check(
    SpecChecker Function(DiagnosticBag, DisplayPaths) make,
  ) {
    final bag = DiagnosticBag();
    final paths = DisplayPaths(dir.path);
    final config = ConfigLoader(bag).load(
      '${dir.path}/typed_openapi.yaml',
    )!;
    return make(bag, paths).checkClients(config);
  }

  test(
    'clients with equal settings but different locks are two runs',
    () async {
      await lockThenAddSchema(
        '  pets: {input: specs/pets.yaml, output: gen/pets}\n'
        '  other: {input: specs/pets.yaml, output: gen/other}\n',
      );
      final checks = check(SpecChecker.new);
      // The clients are in name order: `other` has no section in the lock.
      expect(_typeAt(checks[0].ir!, _inline), 'PetStatus2');
      expect(_typeAt(checks[1].ir!, _inline), 'PetStatus');
    },
  );

  test('SpecChecker.freshNames names from the spec alone', () async {
    await lockThenAddSchema(
      '  pets: {input: specs/pets.yaml, output: gen/pets}\n',
    );
    expect(_typeAt(check(SpecChecker.new).single.ir!, _inline), 'PetStatus');
    final checks = check(SpecChecker.freshNames);
    expect(_typeAt(checks.single.ir!, _inline), 'PetStatus2');
  });

  test('a lock that cannot be read gives no names and is TOA835', () async {
    await lockThenAddSchema(
      '  pets: {input: specs/pets.yaml, output: gen/pets}\n',
    );
    dir.write('typed_openapi.lock', '<<<<<<< HEAD\n');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load('${dir.path}/typed_openapi.yaml')!;
    final checks = SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).checkClients(config);
    expect(_typeAt(checks.single.ir!, _inline), 'PetStatus2');
    expect(bag.all.map((d) => d.code), [DiagnosticCode.apiLockUnusable]);
  });

  test('locks are equal by their names', () {
    final a = NameLock(root: Uri.parse('file:///a.yaml'), types: {'x': 'X'});
    final b = NameLock(root: Uri.parse('file:///a.yaml'), types: {'x': 'X'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(NameLock(root: Uri.parse('file:///a.yaml'))));
  });
}
