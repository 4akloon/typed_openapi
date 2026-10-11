import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

/// A spec read from text and normalized with every rule.
final class NormalizerFixture {
  /// Loads [text] as `api.yaml`, detects its version and normalizes it with
  /// [preset]; the text must load and declare a version.
  NormalizerFixture(String text, {Preset? preset}) {
    final document = SpecLoader(diagnostics).parse(text, 'api.yaml')!;
    final version = OpenApiVersionDetector(diagnostics).detect(document)!;
    result = Normalizer(diagnostics, preset: preset).normalize(
      document,
      version,
    );
  }

  /// Every diagnostic.
  final DiagnosticBag diagnostics = DiagnosticBag();

  /// What the normalizer produced.
  late final NormalizedSpec result;

  /// The diagnostics with [code], in report order.
  List<Diagnostic> of(DiagnosticCode code) => [
    for (final d in diagnostics.sorted)
      if (d.code == code) d,
  ];

  /// The pointers of the diagnostics with [code], in report order.
  List<String?> pointersOf(DiagnosticCode code) => [
    for (final d in of(code)) d.pointer?.value,
  ];
}
