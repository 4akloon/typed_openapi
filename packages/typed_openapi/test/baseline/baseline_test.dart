import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/anchor_index.dart';
import 'package:typed_openapi/src/baseline/baseline.dart';
import 'package:typed_openapi/src/baseline/baseline_loader.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  final fingerprints = Fingerprints(
    AnchorIndex.none(),
    '/work/api.baseline.yaml',
    const DisplayPaths('/work'),
  );

  Diagnostic finding(
    String key, {
    DiagnosticCode code = DiagnosticCode.unknownKey,
    String message = 'Unknown key.',
  }) => Diagnostic(
    code: code,
    severity: code.defaultSeverity,
    message: message,
    file: 'api.yaml',
    pointer: JsonPointer.root.child(key),
  );

  final b = finding('b');
  final a1 = finding('a', message: 'First.');
  final a2 = finding('a', message: 'Second.');
  final missing = finding('a', code: DiagnosticCode.inputNotFound);

  test('of groups equal fingerprints, sorts and skips fixed codes', () {
    final baseline = Baseline.of('api.baseline.yaml', [
      b,
      a2,
      missing,
      a1,
    ], fingerprints);
    final hashA = Fingerprints.hash(
      DiagnosticCode.unknownKey,
      'api.yaml#/a',
      const [],
    );
    final hashB = Fingerprints.hash(
      DiagnosticCode.unknownKey,
      'api.yaml#/b',
      const [],
    );
    expect(
      baseline.toYaml(),
      '# Diagnostics accepted for this client: typed_openapi check\n'
      '# hides them. Written by `typed_openapi baseline create`;\n'
      '# `typed_openapi baseline prune` removes stale entries.\n'
      'version: 1\n'
      'entries:\n'
      '  - fingerprint: "$hashA"\n'
      '    code: "TOA110"\n'
      '    anchor: "api.yaml#/a"\n'
      '    message: "First."\n'
      '    count: 2\n'
      '  - fingerprint: "$hashB"\n'
      '    code: "TOA110"\n'
      '    anchor: "api.yaml#/b"\n'
      '    message: "Unknown key."\n',
    );
  });

  test('of records errors and warnings, not infos', () {
    final info = finding('a', code: DiagnosticCode.exampleScalarType);
    final error = finding('c', code: DiagnosticCode.duplicateOperationId);
    final baseline = Baseline.of('x.yaml', [info, b, error], fingerprints);
    expect(baseline.entries.map((e) => e.code), ['TOA110', 'TOA504']);
  });

  test('an entry never hides an info', () {
    final info = finding('a', code: DiagnosticCode.exampleScalarType);
    final baseline = Baseline('x.yaml', [
      BaselineEntry(fingerprint: fingerprints.of(info)),
    ]);
    final match = baseline.match([info], fingerprints);
    expect(match.shown, [info]);
    expect(match.baselined, isEmpty);
    expect(match.stale.single.$2, 0);
  });

  test('an empty baseline is written as an empty list', () {
    expect(
      const Baseline('x.yaml', []).toYaml(),
      endsWith('version: 1\nentries: []\n'),
    );
  });

  test('the written file reads back without diagnostics', () {
    final written = Baseline.of('api.baseline.yaml', [
      a1,
      a2,
      b,
    ], fingerprints).toYaml();
    final bag = DiagnosticBag();
    final read = BaselineLoader(bag).parse(written, 'b.yaml')!;
    expect(bag.all, isEmpty);
    expect(read.entries.map((e) => (e.anchor, e.count, e.pointer.value)), [
      ('api.yaml#/a', 2, '#/entries/0'),
      ('api.yaml#/b', 1, '#/entries/1'),
    ]);
    expect(read.toYaml(), written);
  });

  group('match', () {
    final baseline = Baseline.of('x.yaml', [a1, b], fingerprints);

    test('accepts up to the count and shows the rest', () {
      final match = baseline.match([a2, a1, b, missing], fingerprints);
      expect(match.baselined, [a1, b]);
      expect(match.shown, [missing, a2]);
      expect(match.stale, isEmpty);
    });

    test('an entry with fewer findings than its count is stale', () {
      final match = baseline.match([b], fingerprints);
      expect(match.baselined, [b]);
      expect(match.stale.map((s) => (s.$1.anchor, s.$2)), [
        ('api.yaml#/a', 0),
      ]);
    });

    test('pruned drops entries without findings and lowers counts', () {
      final twice = Baseline.of('x.yaml', [a1, a2, b], fingerprints);
      final pruned = twice.pruned(twice.match([a1], fingerprints));
      expect(pruned.entries.map((e) => (e.anchor, e.count)), [
        ('api.yaml#/a', 1),
      ]);
    });
  });

  group('BaselineLoader', () {
    List<(DiagnosticCode, Severity, String?)> problems(String text) {
      final bag = DiagnosticBag();
      BaselineLoader(bag).parse(text, 'b.yaml');
      return [for (final d in bag.all) (d.code, d.severity, d.pointer?.value)];
    }

    test('a blank file has no entries and no problems', () {
      final bag = DiagnosticBag();
      expect(
        BaselineLoader(bag).parse('# nothing yet\n', 'b.yaml')!.entries,
        isEmpty,
      );
      expect(bag.all, isEmpty);
    });

    test('rejects a missing or unknown version', () {
      expect(problems('entries: []\n'), [
        (DiagnosticCode.invalidBaseline, Severity.error, '#'),
      ]);
      expect(problems('version: 2\nentries: []\n'), [
        (DiagnosticCode.invalidBaseline, Severity.error, '#/version'),
      ]);
    });

    test('a version that is not an integer must be the integer 1', () {
      final bag = DiagnosticBag();
      BaselineLoader(bag).parse('version: "1"\nentries: []\n', 'b.yaml');
      expect(bag.all.single.message, contains('must be the integer 1'));
      expect(bag.all.single.pointer?.value, '#/version');
    });

    test('skips bad entries and warns about unknown keys and repeats', () {
      expect(
        problems('''
version: 1
entries:
  - {fingerprint: "ABC"}
  - {fingerprint: "0123456789ab", count: 0}
  - {fingerprint: "0123456789ab", note: x}
  - {fingerprint: "0123456789ab"}
  - just text
'''),
        [
          (
            DiagnosticCode.invalidBaseline,
            Severity.error,
            '#/entries/0/fingerprint',
          ),
          (DiagnosticCode.invalidBaseline, Severity.error, '#/entries/1/count'),
          (
            DiagnosticCode.invalidBaseline,
            Severity.warning,
            '#/entries/2/note',
          ),
          (DiagnosticCode.invalidBaseline, Severity.warning, '#/entries/3'),
          (DiagnosticCode.invalidBaseline, Severity.error, '#/entries/4'),
        ],
      );
    });

    test('reports a syntax error as invalid-baseline', () {
      expect(
        problems('version: [1\n').single.$1,
        DiagnosticCode.invalidBaseline,
      );
    });

    test('reports a missing file and a directory', () {
      final dir = TempDir();
      final bag = DiagnosticBag();
      final loader = BaselineLoader(bag);
      expect(
        loader.load('${dir.path}/none.yaml', displayPath: 'none.yaml'),
        isNull,
      );
      expect(loader.load(dir.path, displayPath: 'dir'), isNull);
      expect(bag.all.map((d) => (d.code, d.file)), [
        (DiagnosticCode.baselineNotFound, 'none.yaml'),
        (DiagnosticCode.invalidBaseline, 'dir'),
      ]);
    });
  });
}
