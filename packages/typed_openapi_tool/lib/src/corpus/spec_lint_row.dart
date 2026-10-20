import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'corpus_spec.dart';

/// The lint of one corpus spec next to the framework the corpus names.
final class SpecLintRow {
  /// Creates the row of [spec] with its lint [result].
  const SpecLintRow(this.spec, this.result);

  /// The corpus entry.
  final CorpusSpec spec;

  /// What `typed_openapi lint` found.
  final LintResult result;

  /// The preset the corpus expects the detector to find.
  Preset get expected => spec.expectedPreset;

  /// The preset the detector found.
  Preset get detected => result.detection.preset;

  /// Whether the detector found the preset the corpus expects.
  bool get isDetectionAsExpected => detected == expected;

  /// How many findings have [severity].
  int count(Severity severity) =>
      result.diagnostics.all.where((d) => d.severity == severity).length;

  /// How many findings each diagnostic code has, by code id.
  Map<String, int> get codeCounts {
    final counts = <String, int>{};
    for (final diagnostic in result.diagnostics.all) {
      counts.update(diagnostic.code.id, (n) => n + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
}
