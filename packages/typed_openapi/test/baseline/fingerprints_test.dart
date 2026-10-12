import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/anchor_index.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

import '../helpers/temp_dir.dart';

void main() {
  /// Checks [spec] written to `api.yaml` (and [files] next to it) and
  /// returns its diagnostics with their anchors for a baseline at
  /// [baseline], both relative to the temp directory.
  List<(DiagnosticCode, String, String)> check(
    String spec, {
    Map<String, String> files = const {},
    String baseline = 'api.baseline.yaml',
  }) {
    final dir = TempDir();
    final paths = DisplayPaths(dir.path);
    final path = dir.write('api.yaml', spec);
    files.forEach(dir.write);
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path, displayPath: paths.of(path))!;
    final normalized = Normalizer(
      bag,
    ).normalize(document, OpenApiVersionDetector(bag).detect(document)!);
    final fingerprints = Fingerprints(
      AnchorIndex(normalized.model, normalized.documents),
      baseline,
      paths,
    );
    return [
      for (final d in bag.sorted)
        (d.code, fingerprints.anchorOf(d), fingerprints.of(d)),
    ];
  }

  const petsWithLimit = '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      parameters:
        - {name: page, in: query, schema: {type: integer}}
        - {name: limit, in: query, bogus: 1, schema: {type: integer}}
      responses: {'200': {description: ok}}
''';

  test('anchors a parameter by its address, not its index', () {
    final before = check(petsWithLimit);
    final after = check(
      petsWithLimit.replaceFirst(
        '        - {name: page',
        '        - {name: sort, in: query, schema: {type: string}}\n'
            '        - {name: page',
      ),
    );
    final unknown = before.where((d) => d.$1 == DiagnosticCode.unknownKey);
    expect(
      unknown.single.$2,
      '@/operations/GET ~1pets/parameters/query:limit#/bogus',
    );
    expect(
      after.where((d) => d.$1 == DiagnosticCode.unknownKey).single,
      unknown.single,
    );
  });

  test('an edit elsewhere in the spec keeps the fingerprint', () {
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''';
    final before = check(spec);
    final after = check(
      spec.replaceFirst(
        'components:',
        'paths:\n  /a: {get: {responses: {"200": {description: ok}}}}\n'
            'components:',
      ),
    );
    final tag = before.where((d) => d.$1 == DiagnosticCode.boolRequired);
    expect(tag.single.$2, '@/schemas/Tag/properties/name#/required');
    expect(
      after.where((d) => d.$1 == DiagnosticCode.boolRequired).single,
      tag.single,
    );
  });

  test('anchors a schema in another file by its components key', () {
    final found = check(
      r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {Err: {$ref: "common.yaml#/Error"}}}
''',
      files: {'common.yaml': 'Error: {type: object, bogus: 1}\n'},
    );
    expect(found.single.$2, '@/schemas/Err#/bogus');
  });

  test('anchors a place without an address by the file and pointer, '
      'relative to the baseline file', () {
    final found = check(
      'openapi: 3.0.3\ninfo: {version: "1"}\npaths: {}\n',
      baseline: 'baselines/api.baseline.yaml',
    );
    expect(found.single.$2, '../api.yaml#/info');
  });

  test('a finding with args differs from one at the same place without '
      'them', () {
    final found = check('openapi: 3.0.3\ninfo: {}\npaths: {}\n');
    expect(found.map((d) => (d.$1, d.$2)), [
      (DiagnosticCode.missingRequiredField, 'api.yaml#/info'),
      (DiagnosticCode.missingRequiredField, 'api.yaml#/info'),
    ]);
    expect(found.first.$3, isNot(found.last.$3));
  });

  group('Fingerprints.of', () {
    final fingerprints = Fingerprints(
      AnchorIndex.none(),
      p.join('work', 'api.baseline.yaml'),
      DisplayPaths(p.join(p.rootPrefix(p.current), 'repo')),
    );
    Diagnostic diagnostic(
      String message, {
      DiagnosticCode code = DiagnosticCode.unknownKey,
      String? file = 'work/api.yaml',
    }) => Diagnostic(
      code: code,
      severity: Severity.warning,
      message: message,
      file: file,
      pointer: JsonPointer.parse('#/info/x'),
    );

    test('ignores the message', () {
      expect(
        fingerprints.of(diagnostic('Unknown key "x".')),
        fingerprints.of(diagnostic('The key "x" is not defined.')),
      );
    });

    test('depends on the code', () {
      expect(
        fingerprints.of(diagnostic('m')),
        isNot(
          fingerprints.of(
            diagnostic('m', code: DiagnosticCode.invalidValue),
          ),
        ),
      );
    });

    test('is 12 hex digits of SHA-256 over [code, anchor, args]', () {
      expect(fingerprints.anchorOf(diagnostic('m')), 'api.yaml#/info/x');
      expect(fingerprints.of(diagnostic('m')), 'ed41f0665b98');
      expect(
        Fingerprints.hash(DiagnosticCode.unknownKey, 'api.yaml#/info/x', []),
        'ed41f0665b98',
      );
    });

    test('a diagnostic without a file is anchored by its pointer', () {
      expect(fingerprints.anchorOf(diagnostic('m', file: null)), '#/info/x');
    });
  });
}
