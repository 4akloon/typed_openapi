import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
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
  /// distinct preset, set of disabled rules and overrides file; each client
  /// then gives the diagnostics of that run its own levels
  /// ([ClientConfig.severity]), because levels change how a finding is
  /// reported, not what a run finds. The bag reports a diagnostic the
  /// clients share once. Diagnostics name files
  /// relative to the working directory (see [DisplayPaths]).
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    // A run is a file with a preset, a set of disabled rules and overrides.
    final runs = <(String, Preset?, String, String?), List<Diagnostic>>{};
    for (final client in config.clients) {
      if (only.isNotEmpty && !only.contains(client.name)) continue;
      final rules = (client.disabledRules.toList()..sort()).join(',');
      final run = (
        p.absolute(client.input),
        client.preset,
        rules,
        client.overrides,
      );
      final found = runs[run] ??= _run(client);
      for (final diagnostic in found) {
        final reported = client.severity.apply(diagnostic);
        if (reported != null) _diagnostics.add(reported);
      }
    }
  }

  /// Checks the spec of [client]; returns what the run found, with default
  /// levels.
  List<Diagnostic> _run(ClientConfig client) {
    final found = DiagnosticBag();
    final document = SpecLoader(
      found,
    ).load(client.input, displayPath: _paths.of(client.input));
    if (document == null) return found.all;
    final version = OpenApiVersionDetector(found).detect(document);
    if (version == null) return found.all;
    final overridesPath = client.overrides;
    final overrides = overridesPath == null
        ? null
        : OverrideLoader(
            found,
          ).load(overridesPath, displayPath: _paths.of(overridesPath));
    Normalizer(
      found,
      disabled: client.disabledRules,
      preset: client.preset,
    ).normalize(document, version, overrides: overrides);
    return found.all;
  }
}
