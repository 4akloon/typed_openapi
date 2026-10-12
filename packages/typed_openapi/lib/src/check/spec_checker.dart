import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_loader.dart';

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics]; [_paths] names files
  /// in diagnostics.
  const SpecChecker(this._diagnostics, [this._paths = const DisplayPaths()]);

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// Checks the spec of every client in [config].
  ///
  /// Each spec is loaded, its OpenAPI version detected, and then it is read
  /// into the model with its `$ref`s resolved, changed by the client's
  /// overrides and normalized with the client's rules and preset. An
  /// overrides file that cannot be used is reported and the spec is checked
  /// without it. [only] limits the run to clients with these names; empty
  /// means all. A file shared by several clients is checked once per
  /// distinct preset, set of disabled rules and overrides file; the bag
  /// reports a diagnostic the runs share once. Diagnostics name files
  /// relative to the working directory (see [DisplayPaths]).
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    final loader = SpecLoader(_diagnostics);
    final detector = OpenApiVersionDetector(_diagnostics);
    // A run is a file with a preset, a set of disabled rules and overrides.
    final checked = <(String, Preset?, String, String?)>{};
    for (final client in config.clients) {
      if (only.isNotEmpty && !only.contains(client.name)) continue;
      final rules = (client.disabledRules.toList()..sort()).join(',');
      final overridesPath = client.overrides;
      final run = (
        p.absolute(client.input),
        client.preset,
        rules,
        overridesPath,
      );
      if (!checked.add(run)) continue;
      final document = loader.load(
        client.input,
        displayPath: _paths.of(client.input),
      );
      if (document == null) continue;
      final version = detector.detect(document);
      if (version == null) continue;
      final overrides = overridesPath == null
          ? null
          : OverrideLoader(_diagnostics).load(
              overridesPath,
              displayPath: _paths.of(overridesPath),
            );
      Normalizer(
        _diagnostics,
        disabled: client.disabledRules,
        preset: client.preset,
      ).normalize(document, version, overrides: overrides);
    }
  }
}
