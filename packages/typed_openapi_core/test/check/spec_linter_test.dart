import 'package:test/test.dart';
import 'package:typed_openapi_core/src/check/spec_linter.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/display_paths.dart';
import 'package:typed_openapi_core/src/load/openapi_version.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';
import 'package:typed_openapi_core/src/normalize/normalizer.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  final override = RegExp('override', caseSensitive: false);

  LintResult lintFixture({Preset? preset}) => const SpecLinter().lint(
    Fixtures.path('backend_defects.yaml'),
    preset: preset,
  );

  test('the rules that offer an override also give a source-only fix', () {
    final plain = DiagnosticBag();
    final document = SpecLoader(plain).load(
      Fixtures.path('backend_defects.yaml'),
    )!;
    final version = OpenApiVersionDetector(plain).detect(document)!;
    Normalizer(plain).normalize(document, version);
    final offering = [
      for (final d in plain.all)
        if (d.fix case final fix? when override.hasMatch(fix)) d,
    ];
    expect(
      {for (final d in offering) d.code},
      {
        DiagnosticCode.arrayWithoutItems,
        DiagnosticCode.doubleArray,
        DiagnosticCode.formatOnArray,
        DiagnosticCode.binaryObject,
        DiagnosticCode.contradictoryObjectType,
        DiagnosticCode.exampleTypeMismatch,
        DiagnosticCode.nullableEnumOneOf,
        DiagnosticCode.pathParameterNotInTemplate,
        DiagnosticCode.discriminatorMappingUnresolved,
        DiagnosticCode.wildcardMediaType,
        DiagnosticCode.missingOperationId,
        DiagnosticCode.duplicateOperationId,
      },
    );
    for (final d in offering) {
      final fix = d.forBackend().fix;
      expect(fix, isNotNull, reason: d.code.id);
      expect(fix, isNot(matches(override)), reason: d.code.id);
    }
  });

  test('no fix or hint of a lint mentions an override, for any preset', () {
    for (final preset in Preset.values) {
      final diagnostics = lintFixture(preset: preset).diagnostics.all;
      expect(diagnostics, isNotEmpty);
      for (final d in diagnostics) {
        expect(
          d.fix ?? '',
          isNot(matches(override)),
          reason: '${preset.name} ${d.code.id}',
        );
      }
    }
  });

  test('the preset is detected unless the caller names it', () {
    final detected = lintFixture();
    expect(detected.isChosen, isFalse);
    expect(detected.detection.preset, Preset.generic);
    final chosen = lintFixture(preset: .fastapi);
    expect(chosen.isChosen, isTrue);
    expect(chosen.detection.preset, Preset.fastapi);
  });

  test('a framework preset adds its recipe to the fix', () {
    String? fixOf(LintResult result) => result.diagnostics.all
        .firstWhere((d) => d.code == .duplicateOperationId)
        .fix;
    expect(fixOf(lintFixture(preset: .nestjs)), contains('operationIdFactory'));
    expect(fixOf(lintFixture()), isNot(contains('operationIdFactory')));
  });

  test('a spec that cannot be read is reported without a config step', () {
    final result = const SpecLinter(
      DisplayPaths('/nowhere'),
    ).lint('missing.yaml');
    expect(result.isRead, isFalse);
    final only = result.diagnostics.all.single;
    expect(only.code, DiagnosticCode.inputNotFound);
    expect(only.fix, 'Check the path of the spec file.');
  });

  test('a readable spec is read and builds no IR', () {
    final result = lintFixture();
    expect(result.isRead, isTrue);
    final irCode = RegExp(r'^TOA(25|35|45|55|56|57|65|66|67)\d$');
    expect(
      [
        for (final d in result.diagnostics.all)
          if (irCode.hasMatch(d.code.id)) d.code.id,
      ],
      isEmpty,
    );
  });
}
