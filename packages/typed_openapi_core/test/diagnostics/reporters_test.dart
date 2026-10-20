import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/github_actions_reporter.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/diagnostics/reporters.dart';
import 'package:typed_openapi_core/src/diagnostics/sarif_reporter.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    '{\n  "openapi": "2.0"\n}',
    url: Uri.parse('api.json'),
  );

  DiagnosticBag sample() {
    return DiagnosticBag()
      ..report(
        .unsupportedOpenApiVersion,
        'OpenAPI "2.0" is not supported.',
        file: 'api.json',
        pointer: JsonPointer.root.child('openapi'),
        span: source.span(15, 20),
        fix: 'Emit OpenAPI 3.',
      )
      ..report(
        .positionsUnavailable,
        'No positions.',
        file: 'a.json',
      );
  }

  test('TextReporter sorts by file and prints 1-based positions', () {
    expect(
      const TextReporter().format(sample()),
      'info TOA005 positions-unavailable: No positions.\n'
      '  --> a.json\n'
      'error TOA011 unsupported-openapi-version: '
      'OpenAPI "2.0" is not supported.\n'
      '  --> api.json:2:14\n'
      '  at #/openapi\n'
      '  fix: Emit OpenAPI 3.\n'
      'errors: 1, warnings: 0, infos: 1',
    );
  });

  test('JsonReporter is stable and machine-readable', () {
    final json =
        jsonDecode(const JsonReporter().format(sample()))
            as Map<String, Object?>;
    final first =
        (json['diagnostics']! as List<Object?>)[1] as Map<String, Object?>;
    expect(first, {
      'code': 'TOA011',
      'name': 'unsupported-openapi-version',
      'severity': 'error',
      'message': 'OpenAPI "2.0" is not supported.',
      'file': 'api.json',
      'pointer': '#/openapi',
      'line': 2,
      'column': 14,
      'fix': 'Emit OpenAPI 3.',
      'related': <Object?>[],
      'baselined': false,
    });
    expect(json['summary'], {
      'error': 1,
      'warning': 0,
      'info': 1,
      'baselined': 0,
    });
  });

  group('baselined diagnostics', () {
    DiagnosticBag withBaselined() => sample()
      ..addBaselined(
        Diagnostic(
          code: DiagnosticCode.boolRequired,
          severity: Severity.warning,
          message: 'Accepted.',
          file: 'api.json',
          pointer: JsonPointer.root.child('a'),
        ),
      );

    test('are counted in the summary, not listed', () {
      final text = const TextReporter().format(withBaselined());
      expect(text, isNot(contains('Accepted.')));
      expect(text, endsWith('errors: 1, warnings: 0, infos: 1, baselined: 1'));
      final json =
          jsonDecode(const JsonReporter().format(withBaselined()))
              as Map<String, Object?>;
      expect((json['diagnostics']! as List<Object?>).length, 2);
      expect((json['summary']! as Map<String, Object?>)['baselined'], 1);
    });

    test('are listed and marked with showBaselined', () {
      final text = const TextReporter().format(
        withBaselined(),
        showBaselined: true,
      );
      expect(
        text,
        contains(
          'warning TOA201 bool-required [baselined]: Accepted.\n'
          '  --> api.json\n'
          '  at #/a\n',
        ),
      );
      final json =
          jsonDecode(
                const JsonReporter().format(
                  withBaselined(),
                  showBaselined: true,
                ),
              )
              as Map<String, Object?>;
      final listed = (json['diagnostics']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(listed.map((d) => (d['code'], d['baselined'])), [
        ('TOA005', false),
        ('TOA201', true),
        ('TOA011', false),
      ]);
    });
  });

  test('ReportFormat maps each format to its reporter', () {
    expect(ReportFormat.text.reporter, isA<TextReporter>());
    expect(ReportFormat.json.reporter, isA<JsonReporter>());
    expect(ReportFormat.sarif.reporter, isA<SarifReporter>());
    expect(
      ReportFormat.byOption('github-actions').reporter,
      isA<GitHubActionsReporter>(),
    );
    expect(ReportFormat.values.map((f) => f.option), [
      'text',
      'json',
      'sarif',
      'github-actions',
    ]);
  });

  test('TextReporter lists related locations under the diagnostic', () {
    final bag = DiagnosticBag()
      ..add(
        Diagnostic(
          code: DiagnosticCode.binaryObject,
          severity: Severity.warning,
          message: 'Binary object.',
          file: 'api.json',
          related: [
            RelatedLocation(
              message: 'Introduced by this override.',
              file: 'api.overrides.yaml',
              pointer: JsonPointer.parse('#/schemas/Pet/type'),
            ),
          ],
        ),
      );
    expect(
      const TextReporter().format(bag),
      'warning TOA205 binary-object: Binary object.\n'
      '  --> api.json\n'
      '  related: Introduced by this override.\n'
      '    --> api.overrides.yaml\n'
      '    at #/schemas/Pet/type\n'
      'errors: 0, warnings: 1, infos: 0',
    );
  });
}
