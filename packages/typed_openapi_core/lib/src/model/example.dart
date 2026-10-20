import 'spec_node.dart';

/// An Example Object.
final class Example extends SpecNode {
  /// Creates an example.
  const Example({
    required super.location,
    this.summary,
    this.description,
    this.value,
    this.dataValue,
    this.serializedValue,
    this.externalValue,
    super.extensions,
    super.unknownKeys,
  });

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `value`.
  final (Object?,)? value;

  /// `dataValue` (OpenAPI 3.2).
  final (Object?,)? dataValue;

  /// `serializedValue` (OpenAPI 3.2).
  final String? serializedValue;

  /// `externalValue`.
  final String? externalValue;
}
