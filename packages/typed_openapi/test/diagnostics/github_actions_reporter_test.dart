import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/github_actions_reporter.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    'openapi: 3.0.3\ncomponents:\n  schemas:\n    Pet: {type: object}\n',
    url: Uri.parse('api.yaml'),
  );

  test('writes one annotation per diagnostic and the summary', () {
    final bag = DiagnosticBag()
      ..report(
        .binaryObject,
        'type: object, format: binary; 100% wrong.',
        file: 'specs/a,b.yaml',
        pointer: JsonPointer.parse('#/components/schemas/Pet'),
        span: source.span(48, 61),
        fix: 'Use type: string.',
      )
      ..add(
        Diagnostic(
          code: DiagnosticCode.overrideUnchanged,
          severity: Severity.info,
          message: 'Unchanged.',
          file: 'api.overrides.yaml',
          related: [
            RelatedLocation(
              message: 'Changed here.',
              file: 'api.yaml',
              pointer: JsonPointer.parse('#/components'),
              span: source.span(15, 25),
            ),
          ],
        ),
      )
      ..report(.configNotFound, 'No config.');
    expect(
      const GitHubActionsReporter().format(bag),
      '::error title=TOA901 config-not-found::No config.\n'
      '::notice file=api.overrides.yaml,'
      'title=TOA807 override-unchanged::Unchanged.\n'
      '::notice file=api.yaml,line=2,col=1,endLine=2,endColumn=11,'
      'title=TOA807 override-unchanged (related)::'
      'Changed here.%0Aat #/components\n'
      '::warning file=specs/a%2Cb.yaml,line=4,col=11,endLine=4,endColumn=24,'
      'title=TOA205 binary-object::type: object, format: binary; 100%25 '
      'wrong.%0Aat #/components/schemas/Pet%0Afix: Use type: string.\n'
      'errors: 1, warnings: 1, infos: 1',
    );
  });

  test('marks accepted diagnostics as notices only when asked', () {
    final bag = DiagnosticBag()
      ..addBaselined(
        const Diagnostic(
          code: DiagnosticCode.duplicateOperationId,
          severity: Severity.error,
          message: 'Twice.',
          file: 'api.yaml',
        ),
      );
    expect(
      const GitHubActionsReporter().format(bag),
      'errors: 0, warnings: 0, infos: 0, baselined: 1',
    );
    expect(
      const GitHubActionsReporter().format(bag, showBaselined: true),
      '::notice file=api.yaml,'
      'title=TOA504 duplicate-operation-id (baselined)::Twice.\n'
      'errors: 0, warnings: 0, infos: 0, baselined: 1',
    );
  });
}
