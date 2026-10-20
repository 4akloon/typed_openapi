import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  group('baseline', () {
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
        id: {type: string, required: true}
''';

    DiagnosticBag check(String baseline, {bool strict = false}) {
      final dir = TempDir();
      dir.write('api.yaml', spec);
      dir.write('api.baseline.yaml', baseline);
      final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
''');
      final bag = DiagnosticBag();
      SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).check(ConfigLoader(bag).load(path)!, strictBaseline: strict);
      return bag;
    }

    const name = '@/schemas/Tag/properties/name#/required';
    final nameFingerprint = Fingerprints.hash(
      DiagnosticCode.boolRequired,
      name,
      const [],
    );

    test('hides accepted diagnostics and shows the rest', () {
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint", code: TOA201, anchor: "$name"}
''');
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Tag/properties/id/required',
        ),
      ]);
      expect(bag.baselined.map((d) => d.pointer?.value), [
        '#/components/schemas/Tag/properties/name/required',
      ]);
    });

    test('an entry with nothing to match is stale; strict makes it an '
        'error', () {
      const stale = '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''';
      final bag = check(stale);
      final entry = bag.all.where(
        (d) => d.code == DiagnosticCode.baselineEntryStale,
      );
      expect(entry.single.severity, Severity.warning);
      expect(entry.single.file, 'api.baseline.yaml');
      expect(entry.single.pointer?.value, '#/entries/0');
      expect(entry.single.line, 3);
      expect(
        check(stale, strict: true).all
            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
            .single
            .severity,
        Severity.error,
      );
    });

    test('an entry that accepts more than the check finds is stale', () {
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint", count: 3}
''');
      expect(bag.baselined.length, 1);
      expect(
        bag.all
            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
            .single
            .message,
        'This entry accepts 3 diagnostics (A diagnostic at $nameFingerprint), '
        'but the check finds 1.',
      );
    });

    test('a valid baseline that matches everything reports nothing', () {
      final id = Fingerprints.hash(
        DiagnosticCode.boolRequired,
        '@/schemas/Tag/properties/id#/required',
        const [],
      );
      final bag = check('''
version: 1
entries:
  - {fingerprint: "$nameFingerprint"}
  - {fingerprint: "$id"}
''');
      expect(bag.all, isEmpty);
      expect(bag.baselined.length, 2);
    });

    test('strict applies after the levels of the config', () {
      const stale = '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''';
      for (final level in ['off', 'info']) {
        final dir = TempDir();
        dir.write('api.yaml', spec);
        dir.write('api.baseline.yaml', stale);
        final path = dir.write('typed_openapi.yaml', '''
clients:
  api:
    input: api.yaml
    output: lib/api
    baseline: api.baseline.yaml
    severity: {baseline-entry-stale: $level}
''');
        final bag = DiagnosticBag();
        SpecChecker(
          bag,
          DisplayPaths(dir.path),
        ).check(ConfigLoader(bag).load(path)!, strictBaseline: true);
        expect(
          bag.all
              .where((d) => d.code == DiagnosticCode.baselineEntryStale)
              .map((d) => d.severity),
          [Severity.error],
          reason: level,
        );
      }
    });

    test('an unreadable spec reports its error and no stale entries', () {
      final dir = TempDir();
      dir.write('api.yaml', 'openapi: [3\n');
      dir.write('api.baseline.yaml', '''
version: 1
entries:
  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
''');
      final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
''');
      final bag = DiagnosticBag();
      SpecChecker(
        bag,
        DisplayPaths(dir.path),
      ).check(ConfigLoader(bag).load(path)!);
      expect(bag.all.map((d) => d.code), [DiagnosticCode.parseError]);
    });

    test('a broken baseline file hides nothing', () {
      final bag = check('version: 2\nentries: []\n');
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.boolRequired,
        DiagnosticCode.boolRequired,
        DiagnosticCode.invalidBaseline,
      ]);
      expect(bag.baselined, isEmpty);
    });
  });
}
