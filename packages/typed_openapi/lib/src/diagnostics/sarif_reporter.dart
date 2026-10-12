import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import 'diagnostic.dart';
import 'diagnostic_bag.dart';
import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'reporters.dart';
import 'severity.dart';

/// Formats diagnostics as SARIF 2.1.0, for code scanning in CI.
///
/// One run of the `typed_openapi` tool; its rules are the codes that occur,
/// sorted by id. A result has the code as `ruleId`, the level `error`,
/// `warning` or `note` (for info), the message with the fix, a physical
/// location (the file as a relative URI reference, or a `file:` URI outside
/// the working directory, and the 1-based region) and the JSON pointer as a
/// logical location. A related location (such as the override that
/// introduced the problem) is a `relatedLocations` item. With
/// `showBaselined`, accepted diagnostics are results with an external
/// suppression.
final class SarifReporter implements DiagnosticReporter {
  /// Creates a SARIF reporter.
  const SarifReporter();

  /// The SARIF version written.
  static const version = '2.1.0';

  /// The JSON schema of [version].
  static const schema = 'https://json.schemastore.org/sarif-2.1.0.json';

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...diagnostics.baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final codes = {for (final (d, _) in listed) d.code}.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final index = {for (final (i, code) in codes.indexed) code: i};
    return const JsonEncoder.withIndent('  ').convert({
      r'$schema': schema,
      'version': version,
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'typed_openapi',
              'informationUri': 'https://github.com/4akLoon/typed_openapi',
              'rules': [for (final code in codes) _rule(code)],
            },
          },
          'results': [
            for (final (d, accepted) in listed)
              _result(d, index[d.code]!, accepted: accepted),
          ],
        },
      ],
    });
  }

  static Map<String, Object?> _rule(DiagnosticCode code) => {
    'id': code.id,
    'name': code.slug,
    'defaultConfiguration': {'level': _level(code.defaultSeverity)},
  };

  static Map<String, Object?> _result(
    Diagnostic d,
    int ruleIndex, {
    required bool accepted,
  }) {
    final fix = d.fix;
    return {
      'ruleId': d.code.id,
      'ruleIndex': ruleIndex,
      'level': _level(d.severity),
      'message': {'text': fix == null ? d.message : '${d.message}\nFix: $fix'},
      'locations': [?_location(d.file, d.pointer, d.span)],
      if (d.related.isNotEmpty)
        'relatedLocations': [
          for (final (i, r) in d.related.indexed)
            {
              'id': i + 1,
              'message': {'text': r.message},
              ...?_location(r.file, r.pointer, r.span),
            },
        ],
      if (accepted)
        'suppressions': [
          {'kind': 'external', 'justification': 'Accepted in the baseline.'},
        ],
    };
  }

  static Map<String, Object?>? _location(
    String? file,
    JsonPointer? pointer,
    SourceSpan? span,
  ) {
    if (file == null && pointer == null) return null;
    return {
      if (file != null)
        'physicalLocation': {
          'artifactLocation': {'uri': _uri(file)},
          if (span != null)
            'region': {
              'startLine': span.start.line + 1,
              'startColumn': span.start.column + 1,
              'endLine': span.end.line + 1,
              'endColumn': span.end.column + 1,
            },
        },
      if (pointer != null)
        'logicalLocations': [
          {'fullyQualifiedName': pointer.value, 'kind': 'object'},
        ],
    };
  }

  /// [file] as a URI reference: relative paths keep `/` separators and are
  /// percent-encoded; absolute paths become `file:` URIs.
  static String _uri(String file) => p.isAbsolute(file)
      ? '${p.toUri(file)}'
      : Uri(pathSegments: p.split(file)).toString();

  static String _level(Severity severity) => switch (severity) {
    .error => 'error',
    .warning => 'warning',
    .info => 'note',
  };
}
