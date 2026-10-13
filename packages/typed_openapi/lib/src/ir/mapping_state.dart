import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'mapping_scope.dart';
import 'pending_declaration.dart';

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
    required this.marked,
    required this.constValue,
    required this.notes,
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

  /// Whether the property has `x-typed-tri-state: true`.
  final bool marked;

  /// The value of a constant field.
  final Object? constValue;

  /// What the schema of the property says about its field.
  final FieldNotes notes;

  /// The values of dropped enum branches.
  final List<Object?> knownValues;

  /// Whether the value is a secret that must not be printed.
  final bool sensitive;
}

/// The properties, required names and `additionalProperties` of a model,
/// with its `allOf` parts merged in.
final class ModelParts {
  /// The merged parts of a model.
  const ModelParts(this.properties, this.required, this.additional);

  /// The properties by JSON key, later parts winning.
  final Map<String, Schema> properties;

  /// The names every part requires.
  final Set<String> required;

  /// The `additionalProperties` schema of the last part that has one.
  final Schema? additional;
}

/// What is known about a model while its fields are mapped.
final class ModelSite {
  /// A model of [schema], declared as [pending], used in [direction].
  const ModelSite(this.schema, this.pending, this.direction, this.scope);

  /// The schema the model is made of.
  final SchemaObject schema;

  /// The declaration being filled in.
  final PendingDeclaration pending;

  /// Where the model is used.
  final ModelDirection direction;

  /// The scope its fields are mapped in.
  final MappingScope scope;
}

/// A model before its fields are named.
final class ModelDraft {
  /// A model at [site] with [fields]; [additional] is the type of its
  /// `additionalProperties` made from [additionalSchema].
  const ModelDraft({
    required this.site,
    required this.fields,
    required this.additionalSchema,
    required this.additional,
  });

  /// The model.
  final ModelSite site;

  /// The fields, in the order of the properties.
  final List<FieldDraft> fields;

  /// The `additionalProperties` schema, if any.
  final Schema? additionalSchema;

  /// The type of the values of `additionalProperties`, if it is a schema.
  final DartType? additional;
}

/// What an enum schema says: its values, their kind and the labels the spec
/// gives them.
final class EnumDraft {
  /// An enum of [values] of [kind]; [names] and [descriptions] have one
  /// entry per value when the spec gives them.
  const EnumDraft(this.values, this.kind, this.names, this.descriptions);

  /// The non-null values.
  final List<Object?> values;

  /// The kind of the values.
  final EnumKind kind;

  /// The `x-enum-varnames`, one per value.
  final List<String>? names;

  /// The `x-enum-descriptions`, one per value.
  final List<String?>? descriptions;
}

/// The mutable state that one mapping shares: every call reads and writes
/// the same collections, so they cannot be passed down as a scope.
final class MappingState {
  /// Every declaration created so far, by identity: reaching one again
  /// gives it back.
  final Map<DeclId, PendingDeclaration> pending = {};

  /// The inline enums created so far, by their values, so an equal one is
  /// the same declaration.
  final Map<String, PendingDeclaration> inlineEnums = {};

  /// The subtypes found of each polymorphic base, by its location.
  final Map<SpecLocation, List<SchemaObject>> subtypesOf = {};

  /// The structural aliases being mapped, innermost last, since the last
  /// declaration was entered: meeting one again is a cycle no declaration
  /// breaks.
  final Set<SpecLocation> aliases = {};
}
