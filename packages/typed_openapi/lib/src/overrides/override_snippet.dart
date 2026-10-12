import 'dart:convert';

import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';

/// Writes the override that changes a schema of a spec, as YAML to copy
/// into the overrides file.
///
/// Only schemas the overrides file can address have one: a schema in
/// `components.schemas` (or the schema its `$ref` chain ends at) and a
/// property in its own `properties`.
final class OverrideSnippet {
  /// Creates a writer for schemas of [_model].
  const OverrideSnippet(this._model);

  static final _plain = RegExp(r'^[A-Za-z_$][A-Za-z0-9_.$/-]*$');
  static final _reserved = RegExp(
    r'^(null|true|false|yes|no|on|off|y|n)$',
    caseSensitive: false,
  );

  final SpecModel _model;

  /// The keys that lead to the override of the schema at [location]:
  /// `schemas` and the components key, then `properties` and the property
  /// name for a property; null when the schema has no address.
  List<String>? addressOf(SpecLocation location) {
    final schemas = _model.document.components?.schemas ?? const {};
    // A key that defines its schema wins over a key that refers to one.
    final keys = [
      for (final MapEntry(:key, :value) in schemas.entries)
        if (_isDefinition(value)) key,
      for (final MapEntry(:key, :value) in schemas.entries)
        if (!_isDefinition(value)) key,
    ];
    for (final key in keys) {
      final schema = _model.resolveSchema(schemas[key]!);
      if (schema is! SchemaObject) continue;
      if (schema.location == location) return ['schemas', key];
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        if (property.location == location) {
          return ['schemas', key, 'properties', name];
        }
      }
    }
    return null;
  }

  /// The override of the schema at [location] that sets [fields] (`null`
  /// removes a field), as block YAML; null when the schema has no address or
  /// a value cannot be written as YAML the overrides file reads (a number
  /// that is not finite).
  String? forSchema(SpecLocation location, Map<String, Object?> fields) {
    final address = addressOf(location);
    if (address == null) return null;
    return write(address, fields);
  }

  /// The override at the keys [address] (such as `operations`, `getPet`)
  /// that sets [fields], as block YAML; null when a value cannot be written
  /// as YAML the overrides file reads (a number that is not finite).
  String? write(List<String> address, Map<String, Object?> fields) {
    if (!_isWritable(fields)) return null;
    final lines = <String>[];
    for (final (depth, key) in address.indexed) {
      lines.add('${'  ' * depth}${_key(key)}:');
    }
    final indent = '  ' * address.length;
    for (final MapEntry(:key, :value) in fields.entries) {
      lines.add('$indent${_key(key)}: ${_flow(value)}');
    }
    return lines.join('\n');
  }

  static bool _isWritable(Object? value) => switch (value) {
    null || bool() || int() || String() => true,
    final double number => number.isFinite,
    final Map<Object?, Object?> map => map.entries.every(
      (e) => e.key is String && _isWritable(e.value),
    ),
    final List<Object?> list => list.every(_isWritable),
    _ => false,
  };

  static bool _isDefinition(Schema schema) =>
      schema is! SchemaObject || schema.ref == null;

  static String _key(String key) => _isPlain(key) ? key : jsonEncode(key);

  /// [value] as a YAML flow value; strings that YAML would read as
  /// something else are quoted.
  static String _flow(Object? value) => switch (value) {
    final Map<String, Object?> map =>
      '{${[for (final MapEntry(:key, :value) in map.entries) '${_key(key)}: ${_flow(value)}'].join(', ')}}',
    final List<Object?> list => '[${list.map(_flow).join(', ')}]',
    final String text => _isPlain(text) ? text : jsonEncode(text),
    _ => jsonEncode(value),
  };

  static bool _isPlain(String text) =>
      _plain.hasMatch(text) && !_reserved.hasMatch(text);
}
