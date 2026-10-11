import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/reporters.dart';

void main() {
  final source = SourceFile.fromString(
    '{\n  "openapi": "2.0"\n}',
    url: Uri.parse('api.json'),
  );

  DiagnosticBag sample() {
    return DiagnosticBag()
      ..report(
        DiagnosticCode.unsupportedOpenApiVersion,
        'OpenAPI "2.0" is not supported.',
        file: 'api.json',
        pointer: JsonPointer.root.child('openapi'),
        span: source.span(15, 20),
        fix: 'Emit OpenAPI 3.',
      )
      ..report(
        DiagnosticCode.positionsUnavailable,
        'No positions.',
        file: 'a.json',
      );
  }

  test('formatText sorts by file and prints 1-based positions', () {
    expect(
      formatText(sample().all),
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

  test('formatJson is stable and machine-readable', () {
    final json = jsonDecode(formatJson(sample().all)) as Map<String, Object?>;
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
    });
    expect(json['summary'], {'error': 1, 'warning': 0, 'info': 1});
  });
}
