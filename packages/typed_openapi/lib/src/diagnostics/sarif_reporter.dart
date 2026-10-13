import 'dart:convert';

import 'package:crypto/crypto.dart';
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
///
/// GitHub code scanning needs more than the schema (M11): every rule has a
/// short and a full description and help, every result a partial
/// fingerprint (of its code, file, pointer and message) and a physical
/// location with a region. A file without a position is located at its
/// first line; a result without a file at [defaultFile] (`check` passes the
/// config file), or without a physical location when there is none.
final class SarifReporter implements DiagnosticReporter {
  /// Creates a SARIF reporter that locates a result without a file at
  /// [defaultFile].
  const SarifReporter({this.defaultFile});

  /// The file a result without one is located at.
  final String? defaultFile;

  /// The key of the partial fingerprint of a result.
  static const fingerprintKey = 'typedOpenapi/v1';

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
    'shortDescription': {'text': code.slug},
    'fullDescription': {
      'text':
          '${code.id} ${code.slug}, a diagnostic of typed_openapi '
          '(${_level(code.defaultSeverity)} by default).',
    },
    'help': {'text': _help(code)},
    'defaultConfiguration': {'level': _level(code.defaultSeverity)},
  };

  /// How the level of [code] can be changed, which the config allows only
  /// for codes that are neither fixed nor config codes.
  static String _help(DiagnosticCode code) {
    final catalog = '${code.id} (${code.slug}):';
    if (DiagnosticCode.configCodes.contains(code)) {
      return '$catalog its level cannot be changed.';
    }
    if (DiagnosticCode.fixedCodes.contains(code)) {
      return '$catalog its level can be raised with '
          '`severity: {${code.slug}: error}` in typed_openapi.yaml, not '
          'lowered.';
    }
    return '$catalog set its level with `severity: {${code.slug}: off}` in '
        'typed_openapi.yaml.';
  }

  Map<String, Object?> _result(
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
      'partialFingerprints': {fingerprintKey: _fingerprint(d)},
      'locations': [?_location(d.file ?? defaultFile, d.pointer, d.span)],
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
          'region': {
            'startLine': (span?.start.line ?? 0) + 1,
            'startColumn': (span?.start.column ?? 0) + 1,
            'endLine': (span?.end.line ?? 0) + 1,
            'endColumn': (span?.end.column ?? 0) + 1,
          },
        },
      if (pointer != null)
        'logicalLocations': [
          {'fullyQualifiedName': pointer.value, 'kind': 'object'},
        ],
    };
  }

  /// The partial fingerprint of [d]: the first 16 hexadecimal digits of the
  /// SHA-256 of its code, file, pointer and message.
  ///
  /// The same finding must keep its fingerprint on any machine, so a file
  /// outside the working directory (an absolute path) counts by its file
  /// name alone; a file below the working directory counts by its relative
  /// path.
  static String _fingerprint(Diagnostic d) {
    final file = d.file;
    final stable = file != null && p.isAbsolute(file) ? p.basename(file) : file;
    final text = jsonEncode([d.code.id, stable, d.pointer?.value, d.message]);
    return '${sha256.convert(utf8.encode(text))}'.substring(0, 16);
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
