import 'operation.dart';
import 'spec_node.dart';

/// A Path Item Object.
final class PathItem extends SpecNode {
  /// Creates a path item.
  const PathItem({
    required super.location,
    this.summary,
    this.description,
    this.operations = const {},
    this.additionalOperations = const {},
    this.servers = const [],
    this.parameters = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The fixed operation fields of a path item, in the order the spec lists
  /// them; `query` is OpenAPI 3.2.
  static const methods = [
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
    'trace',
    'query',
  ];

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// Operations by lowercase method from [methods], in the canonical order
  /// of [methods] (not document order).
  final Map<String, Operation> operations;

  /// `additionalOperations` (OpenAPI 3.2): operations by method, with the
  /// method's case as written.
  final Map<String, Operation> additionalOperations;

  /// `servers`.
  final List<Server> servers;

  /// `parameters` shared by every operation of the path.
  final List<RefOr<Parameter>> parameters;
}
