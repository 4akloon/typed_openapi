@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = p.normalize(p.absolute('..', '..'));
  const statuses = {'Supported', 'Partly', 'Reported', 'Not supported'};
  final proofPattern = RegExp('`(packages/[^`]+)`');

  List<List<String>> tableLines({required bool onlyKnown}) {
    final text = File(
      p.join(root, 'packages/typed_openapi/doc/support_matrix.md'),
    ).readAsStringSync();
    final result = <List<String>>[];
    for (final line in text.split('\n')) {
      if (!line.startsWith('|')) continue;
      final cells = line
          .substring(1, line.length - 1)
          .split(RegExp(r'(?<!\\)\|'))
          .map((c) => c.trim())
          .toList();
      if (cells.length != 4 || cells[0] == 'Feature') continue;
      if (cells[0].startsWith('---')) continue;
      if (!onlyKnown || statuses.contains(cells[1])) result.add(cells);
    }
    return result;
  }

  List<List<String>> rows() => tableLines(onlyKnown: true);

  test('every row has a status and at least one proof', () {
    final all = rows();

    expect(all.length, greaterThan(20));
    for (final row in all) {
      expect(proofPattern.hasMatch(row[3]), isTrue, reason: row[0]);
    }
  });

  test('every proof is a test, a fixture or the corpus, and it exists', () {
    for (final row in rows()) {
      for (final match in proofPattern.allMatches(row[3])) {
        final path = match.group(1)!;
        expect(File(p.join(root, path)).existsSync(), isTrue, reason: path);
        expect(
          path.contains('/test/') ||
              path.contains('/fixtures/') ||
              path.endsWith('corpus.yaml'),
          isTrue,
          reason: path,
        );
      }
    }
  });

  test('no row has a status that is not one of the four', () {
    final unknown = [
      for (final row in tableLines(onlyKnown: false))
        if (!statuses.contains(row[1])) '${row[0]}: ${row[1]}',
    ];

    expect(unknown, isEmpty);
  });
}
