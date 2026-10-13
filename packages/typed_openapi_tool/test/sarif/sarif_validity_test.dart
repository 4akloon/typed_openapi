@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/typed_openapi.dart';

import '../helpers/code_scanning_rules.dart';
import '../helpers/json_schema.dart';

/// Every shape of result the reporter writes: a file with a position and a
/// fix, a related location, a file without a position, no file, and an
/// accepted (baselined) one.
DiagnosticBag sample() {
  final source = SourceFile.fromString(
    'openapi: 3.0.3\npaths: {}\n',
    url: Uri.parse('specs/my api.yaml'),
  );
  return DiagnosticBag()
    ..report(
      DiagnosticCode.binaryObject,
      'With a position.',
      file: 'specs/my api.yaml',
      pointer: JsonPointer.parse('#/paths'),
      span: source.span(15, 24),
      fix: 'Do something.',
    )
    ..add(
      Diagnostic(
        code: DiagnosticCode.overrideUnchanged,
        severity: Severity.info,
        message: 'With a related location.',
        file: '/abs/api.overrides.yaml',
        related: [
          RelatedLocation(
            message: 'The schema it changes.',
            file: 'specs/my api.yaml',
            pointer: JsonPointer.parse('#/paths'),
          ),
        ],
      ),
    )
    ..report(DiagnosticCode.binaryObject, 'Without a position.', file: 'a.yaml')
    ..report(DiagnosticCode.configNotFound, 'Without a file.')
    ..addBaselined(
      const Diagnostic(
        code: DiagnosticCode.binaryObject,
        severity: Severity.warning,
        message: 'Accepted.',
        file: 'a.yaml',
      ),
    );
}

void main() {
  final schemaFile = File(
    '.dart_tool/corpus/specs/sarif_schema/sarif-schema-2.1.0.json',
  );
  final schemaSkip = schemaFile.existsSync()
      ? null
      : 'The SARIF schema is not in the cache: run '
            '`dart run bin/corpus.dart fetch sarif_schema`.';
  JsonSchema loadSchema() => JsonSchema(
    jsonDecode(schemaFile.readAsStringSync()) as Map<String, Object?>,
  );
  Map<String, Object?> log(SarifReporter reporter) =>
      jsonDecode(reporter.format(sample(), showBaselined: true))
          as Map<String, Object?>;

  test('the SARIF output is valid against the SARIF 2.1.0 schema', () {
    final schema = loadSchema();
    expect(schema.validate(log(const SarifReporter())), isEmpty);
    expect(
      schema.validate(
        log(const SarifReporter(defaultFile: 'typed_openapi.yaml')),
      ),
      isEmpty,
    );
  }, skip: schemaSkip);

  test('the SARIF output has what GitHub code scanning requires', () {
    const rules = CodeScanningRules();
    expect(
      rules.problems(
        log(const SarifReporter(defaultFile: 'typed_openapi.yaml')),
      ),
      isEmpty,
    );
    // Without a default file a result without one has no location.
    expect(rules.problems(log(const SarifReporter())), [
      '/runs/0/results/0: no locations',
    ]);
  });

  test('the validator finds what the schema forbids', () {
    final schema = loadSchema();
    final bad = log(const SarifReporter())
      ..remove('version')
      ..['extra'] = true;
    expect(schema.validate(bad), [
      contains('"version" is required'),
      contains('"extra" is not allowed'),
    ]);
  }, skip: schemaSkip);
}
