import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_reader.dart';

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
  /// into the model with its `$ref`s resolved. [only] limits the run to
  /// clients with these names; empty means all. A file shared by several
  /// clients is checked once. Spec paths in diagnostics are relative to the
  /// config file's directory.
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    final loader = SpecLoader(_diagnostics);
    final detector = OpenApiVersionDetector(_diagnostics);
    final reader = SpecReader(_diagnostics);
    final configDir = p.dirname(p.absolute(config.file));
    final checked = <String>{};
    for (final client in config.clients) {
      if (only.isNotEmpty && !only.contains(client.name)) continue;
      if (!checked.add(p.absolute(client.input))) continue;
      final document = loader.load(
        client.input,
        displayPath: p.relative(client.input, from: configDir),
      );
      if (document == null) continue;
      final version = detector.detect(document);
      if (version == null) continue;
      reader.read(document, version);
    }
  }
}
