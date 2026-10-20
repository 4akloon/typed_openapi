import '../model/operation.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';

/// The operations of `paths`, by `operationId` and by path template.
final class OperationIndex {
  /// Indexes the operations of [model].
  OperationIndex(SpecModel model) {
    final seen = <SpecLocation>{};
    for (final MapEntry(key: path, :value) in model.document.paths.entries) {
      final item = model.resolve(value);
      if (item == null) continue;
      items[path] = item;
      for (final MapEntry(key: method, value: operation)
          in <MapEntry<String, Operation>>[
            ...item.operations.entries,
            ...item.additionalOperations.entries,
          ]) {
        final id = operation.operationId;
        if (id == null || !seen.add(operation.location)) continue;
        (byId[id] ??= []).add((operation, method, path));
      }
    }
  }

  /// Path items by template.
  final Map<String, PathItem> items = {};

  /// Operations with their method and path, by `operationId`.
  final Map<String, List<(Operation, String, String)>> byId = {};
}
