import '../model/schema.dart';
import '../overrides/override_set.dart';
import 'allof_merger.dart';
import 'custom_types.dart';
import 'dart_type.dart';
import 'enum_mapper.dart';
import 'field_notes_reader.dart';
import 'ir.dart';
import 'mapping_scope.dart';
import 'mapping_state.dart';
import 'mapping_tools.dart';
import 'names.dart';
import 'pending_declaration.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';
import 'type_recursion.dart';

/// Turns an object schema, or the merge of an `allOf`, into a [ModelDecl]:
/// its fields, their types, constraints and tri-state rule (R6.3, R7.2).
final class ModelMapper {
  /// A model mapper that maps the schemas inside a model with [_types].
  ModelMapper(this._tools, this._types)
    : _merger = AllOfMerger(
        _tools.context,
        _tools.queries,
        _tools.modelNotices,
      ),
      _notes = FieldNotesReader(_tools.context, _tools.queries);

  static const _names = DartNames();

  /// The extension that makes a property tri-state with
  /// `tri_state: extension` (R7.2).
  static const triStateExtension = 'x-typed-tri-state';

  final MappingTools _tools;
  final TypeRecursion _types;
  final AllOfMerger _merger;
  final FieldNotesReader _notes;

  /// Maps the fields of the model [schema], and sets how [pending] is built
  /// once it is named.
  void declare(
    SchemaObject schema,
    PendingDeclaration pending,
    MappingScope scope,
  ) {
    final parts = _merger.merge(schema);
    _reportIneffectiveOverrides(schema);
    final site = ModelSite(
      schema,
      pending,
      _modelDirection(schema, pending),
      scope,
    );
    final fields = _fields(site, parts);
    final additionalSchema = parts.additional;
    final draft = ModelDraft(
      site: site,
      fields: fields,
      additionalSchema: additionalSchema,
      additional: additionalSchema == null || additionalSchema is BooleanSchema
          ? null
          : _types.map(
              additionalSchema,
              NameHint.under(pending, 'Value'),
              scope,
            ),
    );
    pending.build = (name, types) => _build(draft, name, types);
  }

  /// Reports what the schema of a model says that is ignored: branches
  /// beside the model, and the overrides that only a union or an enum has.
  void _reportIneffectiveOverrides(SchemaObject schema) {
    _tools.modelNotices.branchesBesideModel(schema);
    _tools.notices.unionHasNoEffect(
      schema,
      'the schema is a model, not a union',
    );
    _tools.notices.exhaustiveOnModel(schema);
  }

  /// Where the model of [schema] is used, which leaves out the `readOnly` or
  /// `writeOnly` properties.
  ModelDirection _modelDirection(
    SchemaObject schema,
    PendingDeclaration pending,
  ) => pending.id.variant != .base
      ? .request
      : _tools.directions.splits(schema)
      ? .response
      : _tools.directions.onlyDirection(schema) ?? .both;

  /// The fields of the model at [site], one for each property of [parts]
  /// that the direction and the overrides do not leave out.
  List<FieldDraft> _fields(ModelSite site, ModelParts parts) => [
    for (final MapEntry(key: json, value: property) in parts.properties.entries)
      ?_field(site, json, property, isRequired: parts.required.contains(json)),
  ];

  /// The field of [property], or null when the model leaves it out.
  FieldDraft? _field(
    ModelSite site,
    String json,
    Schema property, {
    required bool isRequired,
  }) {
    final override = _tools.context.overrides.propertyAt(property.location);
    if (override?.exclude ?? false) return null;
    _reportTriStateOverride(site, override);
    final notes = _notes.of(property);
    if (site.direction == .request && notes.readOnly) return null;
    if (site.direction == .response && notes.writeOnly) return null;
    final custom = override?.dartType;
    final hint = NameHint.under(site.pending, _names.pascal(json) ?? 'Field');
    final (mapped, constant) = _fieldType(property, custom, hint, site.scope);
    return FieldDraft(
      json: json,
      override: override,
      location: property.location,
      valueType: custom == null ? mapped : CustomTypes.of(custom, mapped),
      constValue: constant?.$1,
      notes: notes,
      // A union that stays `JsonValue` accepts anything, and no TOA455
      // says a branch was dropped: it lists no values.
      knownValues: mapped is CoreType && mapped.kind == .json
          ? const []
          : notes.knownValues,
      sensitive:
          notes.writeOnly ||
          notes.secret ||
          _tools.queries.holdsRawSecret(
            property,
            custom == null ? mapped : null,
          ),
      required: isRequired,
      marked:
          property is SchemaObject &&
          property.extensions[triStateExtension] == true,
    );
  }

  /// Reports the `triState` of the override of a property of a model used
  /// in responses only.
  void _reportTriStateOverride(ModelSite site, PropertyOverride? override) {
    if (override != null &&
        override.triState != null &&
        site.direction == .response &&
        !_tools.directions.splits(site.schema)) {
      _tools.notices.triStateOnResponseModel(override);
    }
  }

  /// The type of a property in [scope] (the JSON side of it when a custom
  /// type [custom] replaces it), and its constant, if it has one.
  (DartType, (Object, DartType)?) _fieldType(
    Schema property,
    DartTypeOverride? custom,
    NameHint hint,
    MappingScope scope,
  ) {
    final constant = custom == null ? _constantOf(property, scope) : null;
    final mapped = constant != null
        ? constant.$2
        : custom == null
        ? _types.map(property, hint, scope)
        : _types.replaced(property, hint, scope);
    return (mapped, constant);
  }

  /// The one value of a property that can hold no other, with the type of
  /// the value: a `const` or a one-value enum written inline, not nullable,
  /// of one JSON type (decision 8 of M8). Its field is a constant.
  (Object, DartType)? _constantOf(Schema property, MappingScope scope) {
    if (property is! SchemaObject || property.ref != null || scope.replacing) {
      return null;
    }
    if (SchemaQueries.isNullable(property)) return null;
    final values = SchemaShapes.enumValues(property);
    if (values == null || values.length != 1) return null;
    final value = values.single!;
    return switch (EnumMapper.kindOf(property, values)) {
      .string => (value, const CoreType(.string)),
      .integer => (value, const CoreType(.integer)),
      .number => (value, const CoreType(.number)),
      .boolean => (value, const CoreType(.boolean)),
      null => null,
    };
  }

  /// The declaration of the model [draft], with the fields and the
  /// `additionalProperties` field named in [types].
  ModelDecl _build(ModelDraft draft, String name, NameScope types) {
    final site = draft.site;
    final scope = _memberScope(types);
    final named = [
      for (final field in draft.fields)
        (
          field,
          _tools.names.memberName(
            scope,
            field.json,
            field.override,
            field.location,
            owner: name,
          ),
        ),
    ];
    final extraName = draft.additional == null
        ? null
        : _tools.names.additionalName(scope, name, site.schema.location);
    return ModelDecl(
      id: site.pending.id,
      name: name,
      description: site.schema.description,
      deprecated: site.schema.deprecated,
      additionalProperties: draft.additional,
      additionalPropertiesName: extraName ?? 'additionalProperties',
      additionalSensitive: _additionalIsSecret(draft),
      direction: site.direction,
      fields: [
        for (final (field, fieldName) in named)
          _fieldIr(field, fieldName, site),
      ],
    );
  }

  /// The names of the members of a model, where the types of the library
  /// [types] are reserved: a field named like one would hide the type inside
  /// the class (`other is $2Fa`), and only a name that starts with `$` is
  /// both.
  NameScope _memberScope(NameScope types) => NameScope(
    reserved: {
      ...DartNames.reservedWords,
      ...DartNames.modelMembers,
      ...types.taken,
    },
    reservedSuffix: '_',
  );

  /// Whether the values of `additionalProperties` are secrets.
  bool _additionalIsSecret(ModelDraft draft) {
    final schema = draft.additionalSchema;
    final queries = _tools.queries;
    return schema != null &&
        (SchemaShapes.carriesSecret(schema, refs: queries.refs) ||
            queries.holdsRawSecret(schema, draft.additional));
  }

  /// The field [name] of [field] in the model at [site].
  FieldIr _fieldIr(FieldDraft field, String name, ModelSite site) {
    final notes = field.notes;
    return FieldIr(
      name: name,
      jsonKey: field.json,
      valueType: field.valueType,
      location: field.location,
      required: field.required,
      // A constant is not a parameter, so it is never tri-state, whatever
      // the rule or the override says.
      triState:
          site.direction != .response &&
          field.constValue == null &&
          (field.override?.triState ?? _isTriState(field, site.pending)),
      readOnly: notes.readOnly,
      writeOnly: notes.writeOnly,
      defaultValue: notes.defaultValue,
      description: notes.description,
      deprecated: notes.deprecated,
      constValue: field.constValue,
      constraints: notes.constraints,
      knownValues: field.knownValues,
      sensitive: field.sensitive,
    );
  }

  /// Whether [field] tells "absent" from `null` by the config's rule (R7.2).
  /// A field of any JSON value (`JsonValue`) allows `null` too.
  bool _isTriState(FieldDraft field, PendingDeclaration pending) =>
      switch (_tools.context.config.triState) {
        .patch =>
          pending.patchBody &&
              !field.required &&
              (field.valueType.nullable ||
                  field.valueType == const CoreType(.json)),
        .optional => pending.patchBody && !field.required,
        .extension => field.marked,
      };
}
