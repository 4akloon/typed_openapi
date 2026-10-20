import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'spec_lint_row.dart';

/// The text `corpus lint` prints: a line per spec, the totals by framework
/// and whether the detector found what the corpus names.
final class CorpusLintReport {
  /// Creates the report of [rows].
  const CorpusLintReport(this.rows);

  /// One row per linted spec, in corpus order.
  final List<SpecLintRow> rows;

  /// The rows whose detected preset is not the expected one.
  List<SpecLintRow> get misdetected => [
    for (final row in rows)
      if (!row.isDetectionAsExpected) row,
  ];

  /// The whole report.
  ///
  /// In the `By framework:` table a spec belongs to the framework the corpus
  /// declares, and its `detected` column counts the specs detected as that
  /// framework; a spec with `detects: false` is expected as generic, so it
  /// is not counted there, while the `Detection:` line counts it as expected.
  String format() {
    final lines = <String>[
      ..._table(
        ['spec', 'framework', 'detected', 'errors', 'warnings', 'infos', ''],
        [
          for (final row in rows)
            [
              row.spec.name,
              row.spec.framework.name,
              row.detected.name,
              '${row.count(.error)}',
              '${row.count(.warning)}',
              '${row.count(.info)}',
              row.codeCounts.entries
                  .map((e) => '${e.key}:${e.value}')
                  .join(' '),
            ],
        ],
      ),
      '',
      'By framework:',
      ..._table(
        ['framework', 'specs', 'detected', 'errors', 'warnings', 'infos'],
        [for (final preset in Preset.values) ?_framework(preset)],
      ),
      '',
      'Detection: ${rows.length - misdetected.length} of ${rows.length} as '
          'the corpus expects${misdetected.isEmpty ? '.' : '; the others:'}',
      for (final row in misdetected)
        '  ${row.spec.name}: expected ${row.expected.name}, detected '
            '${row.detected.name} (${row.result.detection.reason})',
    ];
    return '${lines.join('\n')}\n';
  }

  List<String>? _framework(Preset preset) {
    final group = [
      for (final row in rows)
        if (row.spec.framework == preset) row,
    ];
    if (group.isEmpty) return null;
    int total(Severity severity) =>
        group.fold(0, (sum, row) => sum + row.count(severity));
    return [
      preset.name,
      '${group.length}',
      '${group.where((r) => r.detected == preset).length}',
      '${total(.error)}',
      '${total(.warning)}',
      '${total(.info)}',
    ];
  }

  static List<String> _table(List<String> header, List<List<String>> body) {
    final widths = [
      for (var i = 0; i < header.length; i++)
        [header[i], ...body.map((r) => r[i])]
            .map((c) => c.length)
            .reduce(
              (a, b) => a > b ? a : b,
            ),
    ];
    String line(List<String> cells) => [
      for (var i = 0; i < cells.length; i++)
        if (i == 0 || i == cells.length - 1 && header[i].isEmpty)
          cells[i].padRight(widths[i])
        else
          cells[i].padLeft(widths[i]),
    ].join('  ').trimRight();
    return [line(header), ...body.map(line)];
  }
}
