import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

void main() {
  group('an override of an operation the filter leaves out', () {
    const spec = '''
openapi: 3.1.0
info: {title: api, version: "1"}
paths:
  /pets: {get: {operationId: listPets, tags: [pets], responses: {'204': {description: ok}}}}
  /store/orders: {get: {operationId: listOrders, tags: [store], responses: {'204': {description: ok}}}}
''';
    late TempDir dir;
    late String config;

    setUp(() {
      dir = TempDir();
      dir.write('api.yaml', spec);
      dir.write('overrides.yaml', '''
operations:
  GET /store/orders: {name: orders}
''');
      config = dir.write('typed_openapi.yaml', '''
clients:
  api:
    input: api.yaml
    output: lib/api
    overrides: overrides.yaml
    baseline: api.baseline.yaml
    include: {tags: [pets]}
''');
    });

    Future<(int, String, String)> inDir(List<String> args) =>
        CliRunner.run([...args, '-c', config], workingDirectory: dir.path);

    test('text, JSON and SARIF list TOA810 at the entry', () async {
      final (_, text, _) = await inDir(['check']);
      expect(text, contains('warning TOA810 override-operation-not-generated'));
      expect(text, contains('--> overrides.yaml:2:'));
      final (_, json, _) = await inDir(['check', '--format', 'json']);
      final codes = [
        for (final d in (jsonDecode(json) as Map)['diagnostics'] as List)
          (d as Map)['code'],
      ];
      expect(codes, contains('TOA810'));
      final (_, sarif, _) = await inDir(['check', '--format', 'sarif']);
      expect(sarif, contains('"ruleId": "TOA810"'));
      expect(sarif, contains('"uri": "overrides.yaml"'));
    });

    test('a baseline accepts it', () async {
      final (created, _, _) = await inDir(['baseline', 'create']);
      expect(created, 0);
      final (code, out, _) = await inDir(['check']);
      expect(code, 0);
      expect(out, isNot(contains('TOA810')));
      expect(out, contains('baselined: 1'));
    });
  });
}
