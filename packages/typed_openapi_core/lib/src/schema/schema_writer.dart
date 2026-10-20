import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/severity.dart';
import '../normalize/normalizer.dart';
import 'key_spec.dart';
import 'key_type.dart';

/// Writes the JSON Schema (draft-07) of key types and keys.
final class SchemaWriter {
  /// Creates a writer.
  const SchemaWriter();

  /// The dialect of every schema this writer makes.
  static const dialect = 'http://json-schema.org/draft-07/schema#';

  static const _levels = ['error', 'warning', 'info', 'off'];

  /// The schema of values of [type].
  Map<String, Object?> typeOf(KeyType type) => switch (type) {
    BooleanKey() => {'type': 'boolean'},
    StringKey(:final pattern, :final allowsEmpty) => {
      'type': 'string',
      if (!allowsEmpty) 'minLength': 1,
      'pattern': ?pattern,
    },
    IntegerKey(:final minimum) => {'type': 'integer', 'minimum': minimum},
    ChoiceKey(:final values) => {'type': 'string', 'enum': values},
    ListKey(:final item, :final minItems) => {
      'type': 'array',
      'items': typeOf(item),
      if (minItems > 0) 'minItems': minItems,
    },
    ObjectKey(:final keys) => objectOf(keys),
    MapKey() => _mapOf(type),
    CodeLevelsKey() => _codeLevels(),
    RuleFlagsKey() => _ruleFlags(),
    NullableKey(:final inner) => {
      'anyOf': [
        typeOf(inner),
        {'type': 'null'},
      ],
    },
    OneOfKey(:final options) => {'oneOf': options.map(typeOf).toList()},
    FreeObjectKey() => {'type': 'object'},
    AnyKey() => <String, Object?>{},
  };

  /// The schema of the value of [key], with its description.
  Map<String, Object?> keyOf(KeySpec key) => {
    ...typeOf(key.type),
    'description': describe(key),
  };

  /// The schema of a mapping with [keys]; a key named in [references] is a
  /// `$ref` to `#/definitions/<name>`.
  Map<String, Object?> objectOf(
    List<KeySpec> keys, {
    Set<String> references = const {},
  }) => {
    'type': 'object',
    'properties': {
      for (final key in keys)
        key.name: references.contains(key.name)
            ? {r'$ref': '#/definitions/${key.name}'}
            : keyOf(key),
    },
    if (keys.any((key) => key.isRequired))
      'required': [
        for (final key in keys)
          if (key.isRequired) key.name,
      ],
    'additionalProperties': false,
  };

  /// The description of [key], with its default.
  String describe(KeySpec key) => switch (key.defaultValue) {
    null => key.description,
    final value => '${key.description} Default: $value.',
  };

  Map<String, Object?> _mapOf(MapKey type) => {
    'type': 'object',
    'additionalProperties': typeOf(type.value),
    if (type.minProperties > 0) 'minProperties': type.minProperties,
    if (type.keyPattern case final pattern?)
      'propertyNames': {'pattern': pattern},
  };

  /// Every code a config may change, by id and by name; a code that can be
  /// raised but not lowered lists only the levels at least as serious as its
  /// own, and a config code is not listed.
  Map<String, Object?> _codeLevels() => {
    'type': 'object',
    'properties': {
      for (final code in DiagnosticCode.values)
        if (!DiagnosticCode.configCodes.contains(code))
          for (final name in [code.id, code.slug])
            name: {'enum': _levelsOf(code)},
    },
    'additionalProperties': false,
  };

  List<String> _levelsOf(DiagnosticCode code) =>
      DiagnosticCode.fixedCodes.contains(code)
      ? [
          for (final level in Severity.values)
            if (level.index <= code.defaultSeverity.index) level.name,
        ]
      : _levels;

  Map<String, Object?> _ruleFlags() => {
    'type': 'object',
    'properties': {
      for (final name in Normalizer.ruleNames) name: {'type': 'boolean'},
    },
    'additionalProperties': false,
  };
}
