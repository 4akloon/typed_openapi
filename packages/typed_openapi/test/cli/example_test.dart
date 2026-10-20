import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

void main() {
  /// Copies `example/` to a temp directory, so a run writes nothing into the
  /// package.
  String copyOfExample() {
    final target = TempDir().path;
    final source = Directory('example');
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      File(p.join(target, relative))
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
    return target;
  }

  test('the example config has nothing to report', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
    ], workingDirectory: copyOfExample());
    expect(code, 0);
    expect(out, 'errors: 0, warnings: 0, infos: 0\n');
  });

  test('the example generates the client its README calls', () async {
    final directory = copyOfExample();
    final (code, _, _) = await CliRunner.run([
      'generate',
    ], workingDirectory: directory);
    expect(code, 0);
    expect(
      File(
        p.join(directory, 'lib/src/petshop/petshop.dart'),
      ).readAsStringSync(),
      contains('class PetshopClient'),
    );
    expect(
      File(
        p.join(directory, 'lib/src/petshop/api/pets_api.dart'),
      ).readAsStringSync(),
      contains('getPet('),
    );
  });
}
