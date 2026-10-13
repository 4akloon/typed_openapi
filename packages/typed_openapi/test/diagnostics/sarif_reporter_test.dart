import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/sarif_reporter.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  // Absolute on every platform: a bare `/abs` gets the current drive on Windows.
  final absoluteSpec = p.join(
    p.rootPrefix(p.current),
    'abs',
    'specs',
    'api.yaml',
  );

  final source = SourceFile.fromString(
    'openapi: 3.0.3\ncomponents:\n  schemas:\n    Pet: {type: object}\n',
    url: Uri.parse('specs/my api.yaml'),
  );
  final overrides = SourceFile.fromString(
    'schemas:\n  Pet: {format: binary}\n',
    url: Uri.parse('api.overrides.yaml'),
  );

  DiagnosticBag sample() => DiagnosticBag()
    ..report(
      .binaryObject,
      'type: object with format: binary.',
      file: 'specs/my api.yaml',
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
        pointer: JsonPointer.parse('#/schemas/Pet/format'),
        span: overrides.span(16, 22),
        related: [
          RelatedLocation(
            message: 'The schema it changes.',
            file: absoluteSpec,
            pointer: JsonPointer.parse('#/components/schemas/Pet'),
            span: source.span(48, 61),
          ),
        ],
      ),
    )
    ..report(.configNotFound, 'No config.');

  Map<String, Object?> sarif(DiagnosticBag bag, {bool show = false}) =>
      jsonDecode(const SarifReporter().format(bag, showBaselined: show))
          as Map<String, Object?>;

  test('has the shape SARIF 2.1.0 requires', () {
    final log = sarif(sample());
    expectValidSarif(log);
    final run = (log['runs']! as List<Object?>).single as Map<String, Object?>;
    final rules =
        ((run['tool']! as Map<String, Object?>)['driver']!
                as Map<String, Object?>)['rules']!
            as List<Object?>;
    expect(rules.map((r) => (r! as Map<String, Object?>)['id']), [
      'TOA205',
      'TOA807',
      'TOA901',
    ]);
  });

  test('maps codes, levels, locations and related locations', () {
    final results = _results(sarif(sample()));
    expect(results.map((r) => (r['ruleId'], r['level'])), [
      ('TOA901', 'error'),
      ('TOA807', 'note'),
      ('TOA205', 'warning'),
    ]);
    expect(results.first.containsKey('locations'), isTrue);
    expect(results.first['locations'], isEmpty);
    expect(results.last['message'], {
      'text': 'type: object with format: binary.\nFix: Use type: string.',
    });
    expect(results.last['locations'], [
      {
        'physicalLocation': {
          'artifactLocation': {'uri': 'specs/my%20api.yaml'},
          'region': {
            'startLine': 4,
            'startColumn': 11,
            'endLine': 4,
            'endColumn': 24,
          },
        },
        'logicalLocations': [
          {'fullyQualifiedName': '#/components/schemas/Pet', 'kind': 'object'},
        ],
      },
    ]);
    final related = results[1]['relatedLocations']! as List<Object?>;
    expect(related.single, {
      'id': 1,
      'message': {'text': 'The schema it changes.'},
      'physicalLocation': {
        'artifactLocation': {'uri': '${p.toUri(absoluteSpec)}'},
        'region': {
          'startLine': 4,
          'startColumn': 11,
          'endLine': 4,
          'endColumn': 24,
        },
      },
      'logicalLocations': [
        {'fullyQualifiedName': '#/components/schemas/Pet', 'kind': 'object'},
      ],
    });
  });

  test('lists accepted diagnostics as suppressed only when asked', () {
    final bag = sample()
      ..addBaselined(
        const Diagnostic(
          code: DiagnosticCode.boolRequired,
          severity: Severity.warning,
          message: 'Accepted.',
          file: 'a.yaml',
        ),
      );
    expect(
      _results(sarif(bag)).where((r) => r['ruleId'] == 'TOA201'),
      isEmpty,
    );
    final shown = sarif(bag, show: true);
    expectValidSarif(shown);
    expect(
      _results(
        shown,
      ).singleWhere((r) => r['ruleId'] == 'TOA201')['suppressions'],
      [
        {'kind': 'external', 'justification': 'Accepted in the baseline.'},
      ],
    );
  });

  test('an empty report is a run without results', () {
    final log = sarif(DiagnosticBag());
    expectValidSarif(log);
    expect(_results(log), isEmpty);
  });
}

List<Map<String, Object?>> _results(Map<String, Object?> log) =>
    (((log['runs']! as List<Object?>).single
                as Map<String, Object?>)['results']!
            as List<Object?>)
        .cast<Map<String, Object?>>();

/// Checks the parts of the SARIF 2.1.0 schema this tool writes: required
/// properties, enum values, 1-based regions, URI references and rule
/// indexes.
void expectValidSarif(Map<String, Object?> log) {
  expect(log['version'], '2.1.0');
  expect(log[r'$schema'], 'https://json.schemastore.org/sarif-2.1.0.json');
  final runs = log['runs']! as List<Object?>;
  expect(runs, isNotEmpty);
  for (final run in runs.cast<Map<String, Object?>>()) {
    final driver =
        (run['tool']! as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    expect(driver['name'], isA<String>());
    final rules = (driver['rules']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final rule in rules) {
      expect(rule['id'], matches(RegExp(r'^TOA\d{3}$')));
      final level =
          (rule['defaultConfiguration']! as Map<String, Object?>)['level'];
      expect(level, isIn(['none', 'note', 'warning', 'error']));
    }
    for (final result
        in (run['results']! as List<Object?>).cast<Map<String, Object?>>()) {
      expect(result['ruleId'], isA<String>());
      expect(
        rules[result['ruleIndex']! as int]['id'],
        result['ruleId'],
      );
      expect(result['level'], isIn(['none', 'note', 'warning', 'error']));
      expect(
        (result['message']! as Map<String, Object?>)['text'],
        isA<String>(),
      );
      final locations = [
        ...(result['locations']! as List<Object?>),
        ...?(result['relatedLocations'] as List<Object?>?),
      ].cast<Map<String, Object?>>();
      for (final location in locations) {
        final physical = location['physicalLocation'] as Map<String, Object?>?;
        if (physical == null) continue;
        final uri =
            (physical['artifactLocation']! as Map<String, Object?>)['uri']!
                as String;
        expect(uri, isNot(contains(r'\')));
        expect(Uri.parse(uri).toString(), uri);
        final region = physical['region'] as Map<String, Object?>?;
        if (region == null) continue;
        for (final key in [
          'startLine',
          'startColumn',
          'endLine',
          'endColumn',
        ]) {
          expect(region[key], isA<int>().having((v) => v, key, greaterThan(0)));
        }
      }
      final related = (result['relatedLocations'] as List<Object?>?) ?? [];
      final ids = [
        for (final r in related.cast<Map<String, Object?>>()) r['id'] as int,
      ];
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id >= 0), isTrue);
      for (final s
          in ((result['suppressions'] as List<Object?>?) ?? [])
              .cast<Map<String, Object?>>()) {
        expect(s['kind'], isIn(['inSource', 'external']));
      }
    }
  }
}
