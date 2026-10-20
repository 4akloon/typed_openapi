import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import '../schema/override_schema_keys.dart';
import 'generation_field_reader.dart';
import 'override_field_reader.dart';
import 'override_keys.dart';
import 'override_set.dart';

/// Reads the entries of the `schemas` section: a component schema with its
/// properties.
final class SchemaOverrideReader {
  /// Creates a reader that works through [_fields] and [_generation].
  const SchemaOverrideReader(this._fields, this._generation);

  final OverrideFieldReader _fields;
  final GenerationFieldReader _generation;

  /// The schema override [entry] at [at] under [key].
  SchemaOverride schema(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _fields.checkKeys(entry, OverrideKeys.schema, at);
    final spec = _schemaSpec(entry, at, property: false);
    final properties = [
      for (final (name, value, p) in _fields.entries(entry, 'properties', at))
        _property(name, value, p),
    ];
    if (spec.containsKey(r'$ref') && properties.isNotEmpty) {
      _fields.invalid(
        r'"properties" cannot be combined with "$ref": the schema becomes the '
        'reference.',
        at.child('properties'),
      );
      properties.clear();
    }
    return SchemaOverride(
      key: key,
      pointer: at,
      reason: _fields.string(entry, 'reason', at),
      spec: spec,
      name: _fields.string(entry, 'name', at),
      exclude: _fields.boolean(entry, 'exclude', at),
      exhaustive: _fields.boolean(entry, 'exhaustive', at),
      union: _generation.unionMode(entry, at),
      dartType: _generation.dartType(entry, at),
      properties: properties,
    );
  }

  PropertyOverride _property(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _fields.checkKeys(entry, OverrideKeys.property, at);
    return PropertyOverride(
      key: key,
      pointer: at,
      reason: _fields.string(entry, 'reason', at),
      spec: _schemaSpec(entry, at, property: true),
      name: _fields.string(entry, 'name', at),
      exclude: _fields.boolean(entry, 'exclude', at),
      dartType: _generation.dartType(entry, at),
      triState: _fields.boolean(entry, 'triState', at),
      union: _generation.unionMode(entry, at),
    );
  }

  /// The schema fields of [entry]; for a [property], `required` is a
  /// boolean, else the list of required property names.
  Map<String, Object?> _schemaSpec(
    Map<String, Object?> entry,
    JsonPointer at, {
    required bool property,
  }) {
    final spec = <String, Object?>{};
    for (final field in OverrideSchemaKeys.specFieldNames) {
      if (!entry.containsKey(field)) continue;
      final value = entry[field];
      if (!_isValid(field, value, property: property)) {
        _fields.invalid(
          '"$field" ${_expected(field, property: property)}.',
          at.child(field),
        );
        continue;
      }
      spec[field] = value;
    }
    if (spec.containsKey(r'$ref')) {
      _dropSiblingsOfRef(spec, at, property: property);
    }
    return spec;
  }

  static bool _isValid(String field, Object? value, {required bool property}) =>
      switch (field) {
        r'$ref' => value is String && value.isNotEmpty,
        'type' =>
          value == null ||
              SchemaType.values.any(
                (t) => t.wire == value && t != SchemaType.nullType,
              ),
        'nullable' => value is bool,
        'format' => value == null || value is String,
        'required' when property => value is bool,
        'required' =>
          value == null || value is List<Object?> && value.every(_isName),
        'items' || 'discriminator' => value == null || value is Map,
        'additionalProperties' =>
          value == null || value is bool || value is Map,
        'enum' => value == null || value is List<Object?> && value.isNotEmpty,
        _ => false,
      };

  /// Reports and removes the fields of [spec] that cannot go next to `$ref`:
  /// the schema becomes the reference.
  void _dropSiblingsOfRef(
    Map<String, Object?> spec,
    JsonPointer at, {
    required bool property,
  }) {
    for (final field in spec.keys.toList()) {
      if (field == r'$ref' || field == 'nullable') continue;
      if (field == 'required' && property) continue;
      _fields.invalid(
        '"$field" cannot be combined with "\$ref": the schema becomes the '
        'reference.',
        at.child(field),
      );
      spec.remove(field);
    }
  }

  static bool _isName(Object? value) => value is String && value.isNotEmpty;

  static String _expected(String field, {required bool property}) =>
      switch (field) {
        r'$ref' => 'must be a non-empty string',
        'type' =>
          'must be one of string, number, integer, boolean, array, object, or '
              'null to remove it (use "nullable" for null)',
        'nullable' => 'must be true or false',
        'format' => 'must be a string, or null to remove it',
        'required' when property => 'must be true or false',
        'required' => 'must be a list of property names, or null to remove it',
        'items' || 'discriminator' => 'must be an object, or null to remove it',
        'additionalProperties' =>
          'must be true, false or an object, or null to remove it',
        _ => 'must be a non-empty list, or null to remove it',
      };
}
