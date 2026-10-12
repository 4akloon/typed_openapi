import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import '../ir/names.dart';
import '../load/spec_document.dart';
import '../model/operation.dart';

/// A Dart type that a schema, a property or a parameter uses instead of the
/// generated one (R6.8).
final class DartTypeOverride {
  /// Creates a Dart type override.
  const DartTypeOverride({
    required this.type,
    required this.import,
    this.converter,
  });

  /// The Dart type, such as `Money`.
  final String type;

  /// The library that declares [type], such as `package:app/money.dart`.
  final String import;

  /// A class with `fromJson` and `toJson` that converts [type], when the
  /// type itself has no such members.
  final String? converter;

  static final _name = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');
  static final _library = RegExp(
    r'^(package:[A-Za-z_][A-Za-z0-9_]*/\S+|dart:\w+)$',
  );

  /// What makes [value] unusable as the `field` of a custom type in
  /// generated code, or null: `type` and `converter` must be Dart names that
  /// generated code writes as they are (no prefix or type arguments), and
  /// `import` a `package:` or `dart:` library, as relative paths would
  /// depend on where the client is written (R6.8).
  static String? problem(String field, String value) => switch (field) {
    'import' when !_library.hasMatch(value) =>
      '"import" must be a package: or dart: library, such as '
          'package:app/money.dart.',
    'type' || 'converter'
        when !_name.hasMatch(value) ||
            DartNames.reservedWords.contains(value) ||
            DartNames.builtInIdentifiers.contains(value) =>
      '"$field" must be a Dart type name, such as Money.',
    _ => null,
  };
}

/// How a `oneOf` or `anyOf` without a discriminator whose variants share
/// a JSON type is generated (R9.2): the override `union` of a schema and
/// the config key `union`.
enum UnionMode {
  /// As `JsonValue`, with a warning (the default).
  raw,

  /// As a union that tries its variants: a `oneOf` takes the one variant
  /// that decodes, an `anyOf` the first.
  structural,
}

/// What every entry of the overrides file has.
sealed class OverrideEntry {
  /// Creates an entry.
  const OverrideEntry({
    required this.key,
    required this.pointer,
    this.reason,
    this.spec = const {},
  });

  /// The key of the entry as written, such as `getPet` or `id`.
  final String key;

  /// Where the entry is in the overrides file.
  final JsonPointer pointer;

  /// Why the override exists; printed in diagnostics about it.
  final String? reason;

  /// The fields that change the spec, by name, in file order; a `null` value
  /// removes the field from the spec.
  final Map<String, Object?> spec;
}

/// An override of an operation, addressed by `operationId` or by
/// `METHOD /path`.
final class OperationOverride extends OverrideEntry {
  /// Creates an operation override.
  const OperationOverride({
    required super.key,
    required super.pointer,
    super.reason,
    this.operationId,
    this.method,
    this.path,
    this.name,
    this.exclude,
    this.group,
    this.parameters = const [],
    this.requestBody,
    this.responses = const [],
  });

  /// The `operationId` the key names, when it is not `METHOD /path`.
  final String? operationId;

  /// The lowercase method of a `METHOD /path` key.
  final String? method;

  /// The path template of a `METHOD /path` key.
  final String? path;

  /// The name of the generated method.
  final String? name;

  /// Whether the operation is left out of the client.
  final bool? exclude;

  /// The group (API class) the operation belongs to.
  final String? group;

  /// Overrides of the operation's parameters.
  final List<ParameterOverride> parameters;

  /// The override of the request body.
  final BodyOverride? requestBody;

  /// Overrides of responses, by status code.
  final List<ResponseOverride> responses;
}

/// An override of a parameter, addressed by name, or by `in:name` when
/// several parameters share the name.
final class ParameterOverride extends OverrideEntry {
  /// Creates a parameter override.
  const ParameterOverride({
    required super.key,
    required super.pointer,
    required this.parameterName,
    super.reason,
    super.spec,
    this.placement,
    this.name,
    this.dartType,
  });

  /// The name of the parameter in the spec.
  final String parameterName;

  /// The `in` of an `in:name` key.
  final ParameterLocation? placement;

  /// The name of the generated argument.
  final String? name;

  /// The Dart type of the argument.
  final DartTypeOverride? dartType;
}

/// An override of an operation's request body.
final class BodyOverride extends OverrideEntry {
  /// Creates a request body override.
  const BodyOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
  });
}

/// An override of an operation's response, addressed by status code.
final class ResponseOverride extends OverrideEntry {
  /// Creates a response override.
  const ResponseOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
  });
}

/// An override of a schema, addressed by its key in `components.schemas`.
final class SchemaOverride extends OverrideEntry {
  /// Creates a schema override.
  const SchemaOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
    this.name,
    this.exclude,
    this.exhaustive,
    this.union,
    this.dartType,
    this.properties = const [],
  });

  /// The name of the generated type.
  final String? name;

  /// Whether the schema is left out of the client.
  final bool? exclude;

  /// Whether an enum or a union is generated as exhaustive.
  final bool? exhaustive;

  /// How a union without a discriminator is generated (R9.2).
  final UnionMode? union;

  /// The Dart type every use of the schema gets instead of a generated one.
  final DartTypeOverride? dartType;

  /// Overrides of the schema's properties.
  final List<PropertyOverride> properties;
}

/// An override of a property of a schema, addressed by the property name.
final class PropertyOverride extends OverrideEntry {
  /// Creates a property override.
  const PropertyOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
    this.name,
    this.exclude,
    this.dartType,
    this.triState,
    this.union,
  });

  /// The name of the generated field.
  final String? name;

  /// Whether the property is left out of the generated model.
  final bool? exclude;

  /// The Dart type of the field.
  final DartTypeOverride? dartType;

  /// Whether the field tells "absent" from `null`.
  final bool? triState;

  /// How the property's own union without a discriminator is generated
  /// (R9.2), when its schema is one written inline.
  final UnionMode? union;
}

/// The overrides of one client, read from its overrides file.
final class OverrideSet {
  /// Creates a set read from [_source].
  const OverrideSet(
    this._source, {
    this.operations = const [],
    this.schemas = const [],
  });

  final SpecDocument _source;

  /// Operation overrides, in file order.
  final List<OperationOverride> operations;

  /// Schema overrides, in file order.
  final List<SchemaOverride> schemas;

  /// The overrides file as shown to the user.
  String get file => _source.file;

  /// Whether the file has no override.
  bool get isEmpty => operations.isEmpty && schemas.isEmpty;

  /// The source range of the node at [pointer] in [file], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _source.spanOf(pointer);
}
