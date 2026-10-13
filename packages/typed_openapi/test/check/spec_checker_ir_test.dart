import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('builds the IR of each client and reports its diagnostics', () {
    final dir = TempDir();
    dir.write('api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /lists:
    get:
      operationId: getLists
      tags: [lists]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/List'}}}}
components:
  schemas:
    List: {type: object, properties: {id: {type: integer}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b, naming: {group: '{Tag}Service'}}
''');
    final bag = DiagnosticBag();
    final checks = SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).checkClients(ConfigLoader(bag).load(path)!);
    expect(bag.all, isEmpty);
    expect(
      checks.map((c) => c.diagnostics.map((d) => (d.code, d.pointer?.value))),
      [
        [(DiagnosticCode.nameReserved, '#/components/schemas/List')],
        [(DiagnosticCode.nameReserved, '#/components/schemas/List')],
      ],
    );
    expect(checks.map((c) => c.ir!.groups.single.name), [
      'ListsApi',
      'ListsService',
    ]);
    expect(checks.first.ir!.declarations.single.name, 'ListModel');
    expect(
      checks.first.irJson!.toJson(checks.first.ir!)['declarations'],
      [
        {
          'name': 'ListModel',
          'at': 'api.yaml#/components/schemas/List',
          'kind': 'model',
          'direction': 'response',
          'fields': [
            {'name': 'id', 'json': 'id', 'type': 'int?'},
          ],
        },
      ],
    );
  });

  group('runs', () {
    const spec = '''
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

    List<ClientCheck> check(String clients) {
      final dir = TempDir();
      dir.write('api.yaml', spec);
      final path = dir.write('typed_openapi.yaml', clients);
      final bag = DiagnosticBag();
      return SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).checkClients(ConfigLoader(bag).load(path)!);
    }

    test('clients with identical settings share one run', () {
      final checks = check('''
clients:
  a: {input: api.yaml, output: lib/a, naming: {client: Api}}
  b: {input: api.yaml, output: lib/b, naming: {client: Api}}
''');
      expect(identical(checks[0].ir, checks[1].ir), isTrue);
    });

    test('clients that differ only where their filters are written do not '
        'share one', () {
      final checks = check('''
clients:
  a: {input: api.yaml, output: lib/a, include: {tags: [nope]}}
  b: {input: api.yaml, output: lib/b, include: {tags: [nope]}}
''');
      expect(identical(checks[0].ir, checks[1].ir), isFalse);
      expect(
        [
          for (final c in checks)
            for (final d in c.diagnostics)
              if (d.code == DiagnosticCode.filterMatchesNothing)
                d.pointer?.value,
        ],
        ['#/clients/a/include/tags/0', '#/clients/b/include/tags/0'],
      );
    });
  });
}
