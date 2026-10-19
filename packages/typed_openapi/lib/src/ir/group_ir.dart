import 'operation_ir.dart';

/// An API class: the operations of a tag, a path segment or the whole spec
/// (R5.3).
final class GroupIr {
  /// Creates a group; [operations] are sorted by name.
  GroupIr(this.name, List<OperationIr> operations, {this.field = 'api'})
    : operations = List.unmodifiable(
        operations.toList()..sort((a, b) => a.name.compareTo(b.name)),
      );

  /// The Dart name of the class.
  final String name;

  /// The name of the group's field in the root client (`pets` for
  /// `PetsApi`).
  final String field;

  /// The operations, by method name.
  final List<OperationIr> operations;
}
