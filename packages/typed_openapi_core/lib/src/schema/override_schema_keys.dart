import '../model/schema.dart';
import 'config_generation_keys.dart';
import 'key_spec.dart';
import 'key_type.dart';

/// The keys of a schema entry of the overrides file and of a property entry.
///
/// The schema says what the loader accepts, with these gaps, where the
/// loader rejects more: a `$ref` with any field of the schema beside it
/// other than `nullable` (and a property's `required`), and `properties`
/// beside a `$ref`; and a `dartType` name that is a reserved word of Dart.
final class OverrideSchemaKeys {
  OverrideSchemaKeys._();

  /// The `reason` key every entry of the overrides file may have.
  static const reason = KeySpec(
    'reason',
    StringKey(),
    description:
        'Why the override exists; kept in the file for the reader, not used.',
    example: 'The backend omits it.',
  );

  /// The `dartType` key of a parameter, schema or property: the keys are
  /// those of a custom type of the config.
  static final KeySpec dartType = KeySpec.object(
    'dartType',
    ConfigGenerationKeys.customType,
    description:
        'Use this Dart type from a library. The schema does not check that a '
        'type or converter is not a reserved word of Dart.',
  );

  static const _union = KeySpec(
    'union',
    ChoiceKey(['raw', 'structural']),
    description:
        'How a oneOf or anyOf without a discriminator whose variants share '
        'a JSON type is generated.',
    example: 'structural',
  );

  static const _name = KeySpec(
    'name',
    StringKey(),
    description: 'The Dart name.',
    example: 'identifier',
  );

  static const _exclude = KeySpec(
    'exclude',
    BooleanKey(),
    description: 'Whether it is left out of the generated code.',
    example: true,
  );

  static const KeySpec _ref = KeySpec(
    r'$ref',
    StringKey(),
    description:
        'A reference to another schema, such as "#/components/schemas/Pet"; '
        'the schema becomes the reference. Other spec fields beside it are '
        'reported and dropped by the loader, which the schema cannot say; '
        'nullable and the required of a property may stay.',
    example: '#/components/schemas/Other',
  );

  /// The type values of a schema the override can set.
  static final List<String> _types = [
    for (final type in SchemaType.values)
      if (type != SchemaType.nullType) type.wire,
  ];

  static const _requiredList = KeySpec(
    'required',
    NullableKey(ListKey(StringKey())),
    description: 'The names of the required properties; null removes them.',
    example: ['id'],
  );

  static const _requiredFlag = KeySpec(
    'required',
    BooleanKey(),
    description: 'Whether the property is required.',
    example: true,
  );

  /// The spec fields of a schema entry, in the order they are applied.
  static final List<KeySpec> specFields = _specFields(_requiredList);

  /// The names of [specFields].
  static final List<String> specFieldNames = [
    for (final field in specFields) field.name,
  ];

  static List<KeySpec> _specFields(KeySpec required) => [
    _ref,
    ..._shapeFields,
    required,
    ..._structureFields,
  ];

  /// The fields that say what kind of value the schema is.
  static final List<KeySpec> _shapeFields = [
    KeySpec(
      'type',
      NullableKey(ChoiceKey(_types)),
      description: 'The type; null removes it (use nullable for a null value).',
      example: 'string',
    ),
    const KeySpec(
      'nullable',
      BooleanKey(),
      description: 'Whether the value may be null.',
      example: true,
    ),
    const KeySpec(
      'format',
      NullableKey(StringKey(allowsEmpty: true)),
      description: 'The format; null removes it.',
      example: 'uuid',
    ),
  ];

  /// The fields that say what the schema holds.
  static const List<KeySpec> _structureFields = [
    KeySpec(
      'items',
      NullableKey(FreeObjectKey()),
      description: 'The schema of the items, as in the spec; null removes it.',
      example: {'type': 'string'},
    ),
    KeySpec(
      'additionalProperties',
      NullableKey(OneOfKey([BooleanKey(), FreeObjectKey()])),
      description: 'true, false or a schema, as in the spec; null removes it.',
      example: false,
    ),
    KeySpec(
      'enum',
      NullableKey(ListKey(AnyKey(), minItems: 1)),
      description: 'The allowed values; null removes them.',
      example: ['a', 'b'],
    ),
    KeySpec(
      'discriminator',
      NullableKey(FreeObjectKey()),
      description: 'The discriminator, as in the spec; null removes it.',
      example: {'propertyName': 'kind'},
    ),
  ];

  /// The keys of a property entry.
  static final List<KeySpec> property = [
    reason,
    ..._specFields(_requiredFlag),
    _name,
    _exclude,
    dartType,
    const KeySpec(
      'triState',
      BooleanKey(),
      description: 'Whether the property tells null from absent in a PATCH.',
      example: true,
    ),
    _union,
  ];

  /// The keys of a schema entry.
  static final List<KeySpec> schema = [
    reason,
    ...specFields,
    _name,
    _exclude,
    const KeySpec(
      'exhaustive',
      BooleanKey(),
      description: 'Whether the base of an enum or union is sealed.',
      example: false,
    ),
    _union,
    dartType,
    KeySpec(
      'properties',
      NullableKey(MapKey(ObjectKey(property))),
      description:
          r'Property overrides by name. They cannot go with a $ref, which '
          'the schema cannot say: the loader reports it and ignores them.',
      example: {
        'id': {'name': 'identifier'},
      },
    ),
  ];
}
