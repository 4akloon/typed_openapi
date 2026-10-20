import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../normalize/normalizer.dart';
import '../normalize/preset_detection.dart';
import '../normalize/preset_detector.dart';

/// What [SpecLinter] found in one spec.
final class LintResult {
  /// Creates a result.
  const LintResult(
    this.diagnostics,
    this.detection, {
    required this.isChosen,
    required this.isRead,
  });

  /// The findings, with fixes a backend team can follow.
  final DiagnosticBag diagnostics;

  /// The preset the recipes came from and why.
  final PresetDetection detection;

  /// Whether the caller named the preset, rather than it being detected.
  final bool isChosen;

  /// Whether the spec was read far enough to be checked.
  final bool isRead;
}

/// Checks one spec file without a config, for the team that writes the spec.
///
/// It runs the normalizer's rules only: no IR is built, and no fix or hint
/// tells the reader to write an override of the generator.
final class SpecLinter {
  /// Creates a linter; files are named as [_paths] does.
  const SpecLinter([this._paths = const DisplayPaths()]);

  final DisplayPaths _paths;

  /// Lints the spec file at [input]; [preset] names the framework, else it
  /// is detected from the spec.
  LintResult lint(String input, {Preset? preset}) {
    final found = DiagnosticBag();
    final document = SpecLoader(
      found,
    ).load(_paths.absolute(input), displayPath: _paths.of(input));
    final version = document == null
        ? null
        : OpenApiVersionDetector(found).detect(document);
    final detection = switch ((preset, document)) {
      (final chosen?, _) => PresetDetection(chosen, 'it was chosen'),
      (_, null) => const PresetDetection.generic('the spec could not be read'),
      (_, final read?) => const PresetDetector().detect(read.root),
    };
    if (document != null && version != null) {
      Normalizer(
        found,
        preset: detection.preset,
      ).normalize(document, version);
    }
    final backend = DiagnosticBag();
    for (final diagnostic in found.all) {
      backend.add(diagnostic.forBackend());
    }
    return LintResult(
      backend,
      detection,
      isChosen: preset != null,
      isRead: document != null && version != null,
    );
  }
}
