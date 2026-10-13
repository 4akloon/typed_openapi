import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/sarif_reporter.dart';

import '../helpers/cli_runner.dart';
import '../helpers/temp_dir.dart';

/// The single run of the SARIF log [text].
Map<String, Object?> runOf(String text) =>
    ((jsonDecode(text) as Map<String, Object?>)['runs']! as List<Object?>)
            .single!
        as Map<String, Object?>;

/// The results of [run].
List<Map<String, Object?>> resultsOf(Map<String, Object?> run) =>
    (run['results']! as List<Object?>).cast<Map<String, Object?>>();

/// The result of [results] whose message starts with [text].
Map<String, Object?> withMessage(
  List<Map<String, Object?>> results,
  String text,
) => results.firstWhere(
  (r) => ((r['message']! as Map)['text']! as String).startsWith(text),
);

/// The physical location of [result], or null.
Map<String, Object?>? physicalOf(Map<String, Object?> result) =>
    ((result['locations']! as List<Object?>).firstOrNull
            as Map<String, Object?>?)?['physicalLocation']
        as Map<String, Object?>?;

void main() {
  final source = SourceFile.fromString(
    'openapi: 3.0.3\npaths: {}\n',
    url: Uri.parse('api.yaml'),
  );
  DiagnosticBag sample() => DiagnosticBag()
    ..report(
      .binaryObject,
      'With a position.',
      file: 'api.yaml',
      pointer: JsonPointer.parse('#/paths'),
      span: source.span(15, 24),
    )
    ..report(.binaryObject, 'Without a position.', file: 'api.yaml')
    ..report(.configNotFound, 'Without a file.');

  test('every rule has the descriptions and help code scanning needs', () {
    final run = runOf(const SarifReporter().format(sample()));
    final driver =
        (run['tool']! as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    for (final rule in (driver['rules']! as List<Object?>).cast<Map>()) {
      for (final key in ['shortDescription', 'fullDescription', 'help']) {
        expect((rule[key] as Map)['text'], isNotEmpty, reason: key);
      }
    }
  });

  test('every result has a stable partial fingerprint', () {
    final first = resultsOf(runOf(const SarifReporter().format(sample())));
    final again = resultsOf(runOf(const SarifReporter().format(sample())));
    for (final (i, result) in first.indexed) {
      final prints = result['partialFingerprints']! as Map;
      expect(prints.values.single, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(again[i]['partialFingerprints'], prints);
    }
    expect(
      {for (final r in first) (r['partialFingerprints']! as Map).values.single},
      hasLength(3),
    );
  });

  String fingerprintOf(String file, {String workingDirectory = '/work/app'}) {
    final bag = DiagnosticBag()..report(.binaryObject, 'Same.', file: file);
    final reporter = SarifReporter(workingDirectory: workingDirectory);
    final result = resultsOf(runOf(reporter.format(bag))).single;
    return (result['partialFingerprints']! as Map).values.single as String;
  }

  test('outside files with one basename in two directories differ', () {
    expect(
      fingerprintOf('/work/a/api.yaml'),
      isNot(fingerprintOf('/work/b/api.yaml')),
    );
    expect(
      fingerprintOf('/work/api.yaml'),
      isNot(fingerprintOf('api.yaml')),
    );
  });

  test('a fingerprint does not depend on the prefix of the checkout', () {
    expect(
      fingerprintOf('/work/specs/api.yaml'),
      fingerprintOf(
        '/runner/ci/specs/api.yaml',
        workingDirectory: '/runner/ci/app',
      ),
    );
  });

  test('a file without a position is located at its first line', () {
    final results = resultsOf(runOf(const SarifReporter().format(sample())));
    expect(physicalOf(withMessage(results, 'Without a position'))?['region'], {
      'startLine': 1,
      'startColumn': 1,
      'endLine': 1,
      'endColumn': 1,
    });
  });

  test('a result without a file is located at the default file', () {
    final located = resultsOf(
      runOf(
        const SarifReporter(defaultFile: 'typed_openapi.yaml').format(sample()),
      ),
    );
    expect(
      (physicalOf(withMessage(located, 'Without a file'))?['artifactLocation']
          as Map?)?['uri'],
      'typed_openapi.yaml',
    );
    final bare = resultsOf(runOf(const SarifReporter().format(sample())));
    expect(physicalOf(withMessage(bare, 'Without a file')), isNull);
  });

  test('check --format sarif locates a missing config at its path', () async {
    final temp = TempDir();
    final (code, out, _) = await CliRunner.run([
      'check',
      '--format',
      'sarif',
      '-c',
      'missing.yaml',
    ], workingDirectory: temp.path);
    expect(code, isNot(0));
    final result = resultsOf(runOf(out)).single;
    expect(result['ruleId'], 'TOA901');
    expect(
      (physicalOf(result)?['artifactLocation'] as Map?)?['uri'],
      'missing.yaml',
    );
  });

  test('the help of a rule says how its level can be changed', () {
    final bag = DiagnosticBag()
      ..report(.binaryObject, 'Changeable.', file: 'a.yaml')
      ..report(.parseError, 'Fixed.', file: 'a.yaml')
      ..report(.configNotFound, 'Config.', file: 'a.yaml');
    final driver =
        (runOf(const SarifReporter().format(bag))['tool']!
                as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    final help = {
      for (final rule in (driver['rules']! as List<Object?>).cast<Map>())
        rule['id']: (rule['help'] as Map)['text'] as String,
    };
    expect(help.values, everyElement(isNot(contains('catalog'))));
    expect(help['TOA901'], contains('cannot be changed'));
    expect(
      help[DiagnosticCode.parseError.id],
      allOf(contains('raised'), isNot(contains(': off'))),
    );
    expect(help[DiagnosticCode.binaryObject.id], contains(': off}'));
  });
}
