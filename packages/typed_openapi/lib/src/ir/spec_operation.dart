import '../model/operation.dart';

/// An operation of the spec with its method and path.
final class SpecOperation {
  /// Creates the entry for [operation], found at [method] of [path].
  const SpecOperation(this.operation, this.method, this.path, this.item);

  /// The Operation Object.
  final Operation operation;

  /// The HTTP method as the spec writes it: lower case for the fixed
  /// fields, as written for OpenAPI 3.2 `additionalOperations`.
  final String method;

  /// The path template.
  final String path;

  /// The Path Item Object the operation is in.
  final PathItem item;

  /// The key of the operation in the overrides file: its `operationId`, or
  /// `METHOD /path`.
  String get overrideKey =>
      operation.operationId ?? '${method.toUpperCase()} $path';
}
