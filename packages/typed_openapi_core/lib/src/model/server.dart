import 'spec_node.dart';

/// A Server Object.
final class Server extends SpecNode {
  /// Creates a server.
  const Server({
    required super.location,
    this.url,
    this.name,
    this.description,
    this.variables = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `url`, possibly with `{variables}`; required by the spec.
  final String? url;

  /// `name` (OpenAPI 3.2).
  final String? name;

  /// `description`.
  final String? description;

  /// `variables` by name.
  final Map<String, ServerVariable> variables;
}

/// A Server Variable Object.
final class ServerVariable extends SpecNode {
  /// Creates a server variable.
  const ServerVariable({
    required super.location,
    this.enumValues,
    this.defaultValue,
    this.description,
    super.extensions,
    super.unknownKeys,
  });

  /// `enum`.
  final List<String>? enumValues;

  /// `default`; required by the spec.
  final String? defaultValue;

  /// `description`.
  final String? description;
}
