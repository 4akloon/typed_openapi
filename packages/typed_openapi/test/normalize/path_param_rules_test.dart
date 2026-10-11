import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/model/operation.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  String spec(String paths) =>
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\npaths:\n$paths';

  group('declare-missing-path-params', () {
    test('every missing variable is added to the operation', () {
      final run = NormalizerFixture(
        spec('''
  /shops/{shop}/orders/{order}:
    get:
      parameters:
        - {name: limit, in: query, schema: {type: integer}}
      responses: {}
    delete:
      responses: {}
'''),
      );
      final item = run.result.model.resolve(
        run.result.model.document.paths['/shops/{shop}/orders/{order}']!,
      )!;
      final get = item.operations['get']!;
      final names = [
        for (final p in get.parameters) run.result.model.resolve(p)!.name,
      ];
      expect(names, ['limit', 'shop', 'order']);
      final added = run.result.model.resolve(get.parameters[1])!;
      expect(added.placement, ParameterLocation.path);
      expect(added.required, isTrue);
      expect(item.operations['delete']!.parameters, hasLength(2));
      final found = run.of(DiagnosticCode.missingPathParameter);
      expect(found, hasLength(2));
      expect(
        found.first.message,
        'The path /shops/{shop}/orders/{order} has {shop}, {order}, but this '
        'operation declares no path parameter "shop", "order"; they are '
        'added as required string path parameters.',
      );
      expect(found.first.severity, Severity.warning);
      expect(
        found.first.pointer?.value,
        '#/paths/~1shops~1{shop}~1orders~1{order}/get',
      );
    });

    test('parameters of the path item and references count as declared', () {
      final run = NormalizerFixture(
        spec(r'''
  /users/{id}/posts/{post}:
    parameters:
      - {$ref: '#/components/parameters/Id'}
    get:
      parameters:
        - {name: post, in: path, required: true, schema: {type: string}}
      responses: {}
components:
  parameters:
    Id: {name: id, in: path, required: true, schema: {type: string}}
'''),
      );
      expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
      expect(run.of(DiagnosticCode.pathParameterNotInTemplate), isEmpty);
    });
  });

  group(r'a parameter $ref that does not resolve', () {
    test('keeps the operation from getting a guessed parameter', () {
      final run = NormalizerFixture(
        spec(r'''
  /e/{q}:
    get:
      parameters:
        - {$ref: '#/components/parameters/Missing'}
      responses: {}
    delete:
      responses: {}
  /f/{q}:
    parameters:
      - {$ref: '#/components/parameters/Gone'}
    get:
      responses: {}
'''),
      );
      expect(run.of(DiagnosticCode.unresolvedRef), hasLength(2));
      final paths = run.result.documents.root.root['paths']! as Map;
      final e = paths['/e/{q}']! as Map;
      expect((e['get'] as Map)['parameters'], hasLength(1));
      // The other operation of the path has no broken reference.
      expect((e['delete'] as Map)['parameters'], hasLength(1));
      expect(run.pointersOf(DiagnosticCode.missingPathParameter), [
        '#/paths/~1e~1{q}/delete',
      ]);
      expect(
        ((paths['/f/{q}']! as Map)['get'] as Map),
        isNot(contains('parameters')),
      );
    });
  });

  group(r'an operation written as a $ref', () {
    test('is skipped by both rules and left to TOA107', () {
      final run = NormalizerFixture(
        spec(r'''
  /users/{id}:
    get: {$ref: '#/components/x-ops/GetUser'}
'''),
      );
      expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
      expect(run.of(DiagnosticCode.pathParameterNotInTemplate), isEmpty);
      expect(run.of(DiagnosticCode.refNotAllowed), isNotEmpty);
    });
  });

  group('path-param-not-in-template', () {
    test('a renamed or differently cased parameter is an error', () {
      final run = NormalizerFixture(
        spec('''
  /users/{id}:
    get:
      parameters:
        - {name: userId, in: path, required: true, schema: {type: string}}
        - {name: ID, in: path, required: true, schema: {type: string}}
      responses: {}
'''),
      );
      final found = run.of(DiagnosticCode.pathParameterNotInTemplate);
      expect(found.map((d) => d.pointer?.value), [
        '#/paths/~1users~1{id}/get/parameters/0',
        '#/paths/~1users~1{id}/get/parameters/1',
      ]);
      expect(found.first.severity, Severity.error);
      expect(found.last.message, endsWith('which writes it as {id}.'));
      // {id} is not added: the case mismatch is the finding.
      expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
    });
  });
}
