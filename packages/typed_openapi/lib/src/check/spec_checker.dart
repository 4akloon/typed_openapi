import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_loader.dart';

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics].
  const SpecChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Checks the spec of every client in [config].
  ///
  /// Each spec is loaded, its OpenAPI version detected, and then it is read
  /// into the model with its `$ref`s resolved, changed by the client's
  /// overrides and normalized with the client's rules and preset. An
  /// overrides file that cannot be used is reported and the spec is checked
  /// without it. [only] limits the run to clients with these names; empty
  /// means all. A file shared by several clients is checked once per
  /// distinct preset, set of disabled rules and overrides file; the bag
  /// reports a diagnostic the runs share once. Spec and overrides paths in
  /// diagnostics are relative to the config file's directory.
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    final loader = SpecLoader(_diagnostics);
    final detector = OpenApiVersionDetector(_diagnostics);
    final configDir = p.dirname(p.absolute(config.file));
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
        displayPath: p.relative(client.input, from: configDir),
      );
      if (document == null) continue;
      final version = detector.detect(document);
      if (version == null) continue;
      final overrides = overridesPath == null
          ? null
          : OverrideLoader(_diagnostics).load(
              overridesPath,
              displayPath: p.relative(overridesPath, from: configDir),
            );
      Normalizer(
        _diagnostics,
        disabled: client.disabledRules,
        preset: client.preset,
      ).normalize(document, version, overrides: overrides);
    }
  }
}
