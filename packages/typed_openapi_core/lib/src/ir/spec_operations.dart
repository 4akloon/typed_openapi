import '../model/operation.dart';
import 'ir_context.dart';
import 'spec_operation.dart';

/// Lists the operations of a spec.
final class SpecOperations {
  const SpecOperations._();

  /// The operations of `paths`, by location, with `additionalOperations`
  /// (OpenAPI 3.2), and how many operations are written as a `$ref` and so
  /// left out. A path item shared through `$ref` gives its operations to
  /// every path that uses it.
  static (List<SpecOperation>, int) of(IrContext context) {
    final result = <SpecOperation>[];
    var refs = 0;
    for (final MapEntry(key: path, :value)
        in context.model.document.paths.entries) {
      final item = context.model.resolve(value);
      if (item == null) continue;
      for (final MapEntry(key: method, value: operation)
          in <MapEntry<String, Operation>>[
            ...item.operations.entries,
            ...item.additionalOperations.entries,
          ]) {
        // An operation written as a `$ref` is empty; TOA107 reports it.
        if (operation.unknownKeys.containsKey(r'$ref')) {
          refs++;
          continue;
        }
        result.add(SpecOperation(operation, method, path, item));
      }
    }
    result.sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return a.method.compareTo(b.method);
    });
    return (result, refs);
  }
}
