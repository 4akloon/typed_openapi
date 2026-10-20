import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /lists:
    get:
      operationId: getLists
      tags: [lists]
      responses:
        "200": {description: ok}
''';

List<ClientCheck> _check(String clients) {
  final dir = TempDir();
  dir.write('api.yaml', _spec);
  final path = dir.write('typed_openapi.yaml', clients);
  final bag = DiagnosticBag();
  return SpecChecker(
    bag,
    DisplayPaths(dir.path),
  ).checkClients(ConfigLoader(bag).load(path)!);
}

void main() {
  test('clients whose root client is named after them do not share a run', () {
    final checks = _check('''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b}
''');
    expect(identical(checks[0].ir, checks[1].ir), isFalse);
    expect([for (final c in checks) c.ir?.root.name], ['AClient', 'BClient']);
  });

  test('naming.client names the root client of every client it is set for', () {
    final checks = _check('''
defaults: {naming: {client: Api}}
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b}
''');
    expect(identical(checks[0].ir, checks[1].ir), isTrue);
    expect(checks[0].ir?.root.name, 'Api');
  });
}
