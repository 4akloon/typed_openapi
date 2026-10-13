import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  const spec = '''
openapi: 3.0.3
info: {title: Shop, version: "1"}
paths:
  /orders:
    get: {operationId: list, responses: {}}
    post: {responses: {}}
  /orders/archive:
    get: {operationId: list, responses: {}}
''';

  test('missing-operation-id is info at the operation', () {
    final d = NormalizerFixture(spec).of(DiagnosticCode.missingOperationId);
    expect(d.single.pointer?.value, '#/paths/~1orders/post');
    expect(d.single.severity, Severity.info);
  });

  test(r'an operation written as a $ref is left to ref-not-allowed', () {
    final run = NormalizerFixture(r'''
openapi: 3.0.3
info: {title: Shop, version: "1"}
paths:
  /orders/{id}:
    get: {$ref: resources/orders/get.yml}
''');
    expect(run.of(DiagnosticCode.missingOperationId), isEmpty);
    expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
    expect(run.of(DiagnosticCode.refNotAllowed), hasLength(1));
  });

  test('duplicate-operation-id names the first owner of the id', () {
    final d = NormalizerFixture(spec).of(DiagnosticCode.duplicateOperationId);
    expect(
      d.single.pointer?.value,
      '#/paths/~1orders~1archive/get/operationId',
    );
    expect(d.single.severity, Severity.error);
    expect(
      d.single.message,
      'operationId "list" is also the id of the operation at '
      '#/paths/~1orders/get; method names would clash.',
    );
  });

  test('presets add their recipes', () {
    expect(
      NormalizerFixture(
        spec,
        preset: .aspnet,
      ).of(DiagnosticCode.missingOperationId).single.fix,
      contains('[EndpointName("getUser")]'),
    );
    for (final (preset, recipe) in [
      (Preset.nestjs, 'operationIdFactory'),
      (Preset.fastapi, 'generate_unique_id_function'),
      (Preset.springdoc, '@Operation(operationId'),
    ]) {
      expect(
        NormalizerFixture(
          spec,
          preset: preset,
        ).of(DiagnosticCode.duplicateOperationId).single.fix,
        contains(recipe),
      );
    }
  });

  test('the TOA504 fix does not suggest a name override as the cure', () {
    final fix = NormalizerFixture(
      spec,
    ).of(DiagnosticCode.duplicateOperationId).single.fix;
    expect(fix, contains('lower TOA504'));
    expect(fix, isNot(contains('or override the method name')));
  });
}
