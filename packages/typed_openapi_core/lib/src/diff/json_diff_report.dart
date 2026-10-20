import 'dart:convert';

import 'api_change.dart';

/// The `json` report of `typed_openapi diff`: per client the count of each
/// category and every change, as [ApiChange.toJson] writes it.
final class JsonDiffReport {
  /// Creates the report.
  const JsonDiffReport();

  /// The report of the changes of each client, by client name.
  String format(Map<String, List<ApiChange>> clients) {
    final names = clients.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'clients': {
        for (final name in names)
          name: {
            'counts': {
              for (final category in ChangeCategory.values)
                category.label: clients[name]!
                    .where((c) => c.category == category)
                    .length,
            },
            'changes': [for (final c in clients[name]!) c.toJson()],
          },
      },
    });
  }
}
