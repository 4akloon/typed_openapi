import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'override_set.dart';

/// An override entry and the node of the spec model it names.
sealed class OverrideTarget {
  /// Creates a target.
  const OverrideTarget();

  /// The entry of the overrides file.
  OverrideEntry get entry;

  /// The node the entry changes.
  SpecNode get node;
}

/// An operation an [OperationOverride] names.
final class OperationTarget extends OverrideTarget {
  /// Creates a target.
  const OperationTarget(this.entry, this.node);

  @override
  final OperationOverride entry;

  @override
  final Operation node;
}

/// A parameter of an operation; a shared parameter (path-level or `$ref`)
/// is the node where it is defined.
final class ParameterTarget extends OverrideTarget {
  /// Creates a target.
  const ParameterTarget(this.entry, this.node);

  @override
  final ParameterOverride entry;

  @override
  final Parameter node;
}

/// A request body or a response, with the media types of its `content`.
final class ContentTarget extends OverrideTarget {
  /// Creates a target.
  const ContentTarget(this.entry, this.node);

  /// A [BodyOverride] or a [ResponseOverride].
  @override
  final OverrideEntry entry;

  /// A [RequestBody] or a [Response].
  @override
  final SpecNode node;
}

/// A schema in `components.schemas`: the schema its `$ref` chain ends at.
final class SchemaTarget extends OverrideTarget {
  /// Creates a target.
  const SchemaTarget(this.entry, this.node);

  @override
  final SchemaOverride entry;

  @override
  final SchemaObject node;
}

/// A property of a schema: the property schema as written, not where its
/// `$ref` points, so that only this property changes.
final class PropertyTarget extends OverrideTarget {
  /// Creates a target.
  const PropertyTarget(this.entry, this.owner, this.node);

  @override
  final PropertyOverride entry;

  /// The object schema that has the property.
  final SchemaObject owner;

  @override
  final Schema node;
}
