import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'dart_type.dart';
import 'ir.dart';

/// A variant of a union being built: its type, the schema a `$ref` branch
/// (or a subtype) is, the branch, and, for the variant of any JSON value,
/// the JSON types it takes.
final class VariantDraft {
  /// A variant of [type] made from [branch]; [target] is the schema a `$ref`
  /// branch or a subtype names.
  VariantDraft(this.type, this.target, this.branch);

  /// The Dart type of the variant.
  final DartType type;

  /// The schema the branch refers to, when it is a `$ref` or a subtype.
  final SpecLocation? target;

  /// The branch as written.
  final Schema branch;

  /// The JSON types the variant of any JSON value takes.
  final List<JsonKind> kinds = [];

  /// The other branches that make up a variant of any JSON value, besides
  /// [branch].
  final List<Schema> also = [];
}

/// What a property's schema says about its field (`SchemaMapper._notesOf`).
final class FieldNotes {
  /// Notes of a property; the defaults are those of a schema that says
  /// nothing.
  const FieldNotes({
    this.knownValues = const [],
    this.constraints = const ConstraintsIr(),
    this.description,
    this.defaultValue,
    this.deprecated = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.secret = false,
  });

  /// The values of dropped enum branches, for the doc comment.
  final List<Object?> knownValues;

  /// The constraints of the field.
  final ConstraintsIr constraints;

  /// The description.
  final String? description;

  /// The default, boxed so that `null` can be one.
  final (Object?,)? defaultValue;

  /// Whether the field is deprecated.
  final bool deprecated;

  /// Whether the field is `readOnly`.
  final bool readOnly;

  /// Whether the field is `writeOnly`.
  final bool writeOnly;

  /// Whether the value is a secret that must not be printed.
  final bool secret;
}

/// A property of a model, before field names are given.
final class FieldDraft {
  /// A property of a model with everything its field needs but the name.
  FieldDraft({
    required this.json,
    required this.override,
    required this.location,
    required this.valueType,
    required this.required,
    required this.readOnly,
    required this.writeOnly,
    required this.marked,
    required this.defaultValue,
    required this.description,
    required this.deprecated,
    required this.constValue,
    required this.constraints,
    required this.knownValues,
    required this.sensitive,
  });

  /// The key of the property in the JSON object.
  final String json;

  /// The override of the property, if any.
  final PropertyOverride? override;

  /// Where the property schema is written.
  final SpecLocation location;

  /// The type of the value.
  final DartType valueType;

  /// Whether the property is in `required`.
  final bool required;

  /// Whether the property is `readOnly`.
  final bool readOnly;

  /// Whether the property is `writeOnly`.
  final bool writeOnly;

  /// Whether the property has `x-typed-tri-state: true`.
  final bool marked;

  /// The default, boxed so that `null` can be one.
  final (Object?,)? defaultValue;

  /// The description.
  final String? description;

  /// Whether the property is deprecated.
  final bool deprecated;

  /// The value of a constant field.
  final Object? constValue;

  /// The constraints of the property.
  final ConstraintsIr constraints;

  /// The values of dropped enum branches.
  final List<Object?> knownValues;

  /// Whether the value is a secret that must not be printed.
  final bool sensitive;
}
