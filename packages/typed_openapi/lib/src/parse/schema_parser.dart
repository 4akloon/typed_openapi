import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reads Schema Objects of OpenAPI 3.0, 3.1 and 3.2 into [Schema]s.
///
/// Every keyword of any of those versions is read, whatever version the
/// document declares; version-specific ones are noted in the context's
/// index for `DialectChecker`.
final class SchemaParser {
  /// Creates a parser that reads from [_context].
  const SchemaParser(this._context);

  /// Keywords the spec defines but the model does not type.
  static const _accepted = ['xml', 'externalDocs'];

  /// JSON Schema 2020-12 keywords kept raw in [SchemaObject.otherKeywords].
  static const _rawKeywords = [
    r'$id',
    r'$schema',
    r'$anchor',
    r'$dynamicRef',
    r'$dynamicAnchor',
    r'$defs',
    r'$comment',
    r'$vocabulary',
    'if',
    'then',
    'else',
    'dependentSchemas',
    'dependentRequired',
    'patternProperties',
    'propertyNames',
    'contains',
    'minContains',
    'maxContains',
    'unevaluatedItems',
    'unevaluatedProperties',
  ];

  final ParseContext _context;

  /// Reads the schema [raw] at [pointer]; null after reporting when [raw] is
  /// neither an object nor a boolean.
  ///
  /// A boolean is noted as a 3.1 construct unless [booleanIsClassic]: 3.0
  /// allows `additionalProperties: true`.
  Schema? parse(
    Object? raw,
    JsonPointer pointer, {
    bool booleanIsClassic = false,
  }) {
    if (raw is bool) {
      if (!booleanIsClassic) _context.note(.booleanSchema, pointer);
      return _context.register(
        BooleanSchema(location: _context.locate(pointer), value: raw),
      );
    }
    if (raw is! Map<String, Object?>) {
      _context.report(
        .invalidValue,
        'A schema must be an object or a boolean, not '
        '${ObjectReader.describe(raw)}; it is ignored.',
        pointer,
      );
      return null;
    }
    return _object(ObjectReader(_context, raw, pointer));
  }

  SchemaObject _object(ObjectReader r) {
    final ref = r.string(r'$ref');
    if (ref != null) {
      _context.index.refs.add(RefUse(r.location, ref, .schema));
    }
    if (r.has(r'$id')) {
      _context.report(
        .refBaseIgnored,
        r'"$id" changes the base URI of "$ref"s inside this schema; they '
        'are resolved against the file location instead.',
        r.pointer.child(r'$id'),
      );
    }
    final at = r.pointer;
    for (final (key, feature) in _notedKeys) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    r.accept(_accepted);
    final schema = SchemaObject(
      location: r.location,
      ref: ref,
      types: _types(r),
      nullable: r.boolean('nullable'),
      format: r.string('format'),
      title: r.string('title'),
      description: r.string('description'),
      deprecated: r.boolean('deprecated') ?? false,
      readOnly: r.boolean('readOnly') ?? false,
      writeOnly: r.boolean('writeOnly') ?? false,
      defaultValue: r.value('default'),
      constValue: r.value('const'),
      enumValues: r.rawList('enum'),
      example: r.value('example'),
      examples: r.rawList('examples') ?? const [],
      properties: r.map('properties', parse) ?? const {},
      required: r.strings('required') ?? const [],
      additionalProperties: _schemaAt(
        r,
        'additionalProperties',
        booleanIsClassic: true,
      ),
      minProperties: r.count('minProperties'),
      maxProperties: r.count('maxProperties'),
      items: _schemaAt(r, 'items'),
      prefixItems: r.list('prefixItems', parse) ?? const [],
      minItems: r.count('minItems'),
      maxItems: r.count('maxItems'),
      uniqueItems: r.boolean('uniqueItems') ?? false,
      allOf: r.list('allOf', parse) ?? const [],
      oneOf: r.list('oneOf', parse) ?? const [],
      anyOf: r.list('anyOf', parse) ?? const [],
      not: _schemaAt(r, 'not'),
      discriminator: r.object('discriminator', _discriminator),
      minimum: r.number('minimum'),
      maximum: r.number('maximum'),
      exclusiveMinimum: _bound(r, 'exclusiveMinimum'),
      exclusiveMaximum: _bound(r, 'exclusiveMaximum'),
      exclusiveMinimumFlag: _flag(r, 'exclusiveMinimum'),
      exclusiveMaximumFlag: _flag(r, 'exclusiveMaximum'),
      multipleOf: r.number('multipleOf'),
      minLength: r.count('minLength'),
      maxLength: r.count('maxLength'),
      pattern: r.string('pattern'),
      contentMediaType: r.string('contentMediaType'),
      contentEncoding: r.string('contentEncoding'),
      contentSchema: _schemaAt(r, 'contentSchema'),
      otherKeywords: Map.unmodifiable({
        for (final key in _rawKeywords)
          if (r.value(key) case (final raw,)) key: raw,
      }),
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    );
    return _context.register(schema);
  }

  static const _notedKeys = [
    ('nullable', SpecFeature.nullable),
    ('const', SpecFeature.constKeyword),
    ('prefixItems', SpecFeature.prefixItems),
    ('examples', SpecFeature.schemaExamples),
    ('contentMediaType', SpecFeature.contentKeywords),
    ('contentEncoding', SpecFeature.contentKeywords),
    ('contentSchema', SpecFeature.contentKeywords),
    (r'$id', SpecFeature.jsonSchemaKeyword),
    (r'$schema', SpecFeature.jsonSchemaKeyword),
    (r'$anchor', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicRef', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicAnchor', SpecFeature.jsonSchemaKeyword),
    (r'$defs', SpecFeature.jsonSchemaKeyword),
    (r'$comment', SpecFeature.jsonSchemaKeyword),
    (r'$vocabulary', SpecFeature.jsonSchemaKeyword),
    ('if', SpecFeature.jsonSchemaKeyword),
    ('then', SpecFeature.jsonSchemaKeyword),
    ('else', SpecFeature.jsonSchemaKeyword),
    ('dependentSchemas', SpecFeature.jsonSchemaKeyword),
    ('dependentRequired', SpecFeature.jsonSchemaKeyword),
    ('patternProperties', SpecFeature.jsonSchemaKeyword),
    ('propertyNames', SpecFeature.jsonSchemaKeyword),
    ('contains', SpecFeature.jsonSchemaKeyword),
    ('minContains', SpecFeature.jsonSchemaKeyword),
    ('maxContains', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedItems', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedProperties', SpecFeature.jsonSchemaKeyword),
  ];

  List<SchemaType> _types(ObjectReader r) {
    final raw = r.value('type');
    if (raw == null) return const [];
    final at = r.pointer.child('type');
    final (type,) = raw;
    if (type is List<Object?>) _context.note(.typeList, at);
    final names = type is List<Object?> ? type : [type];
    final types = <SchemaType>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final itemAt = type is List<Object?> ? at.child(i) : at;
      final known = name is String ? SchemaType.byWire[name] : null;
      if (known == null) {
        _context.report(
          .invalidValue,
          name is String
              ? 'Unknown type "$name"; it is ignored.'
              : 'A type must be a string, not ${ObjectReader.describe(name)}; '
                    'it is ignored.',
          itemAt,
          fix: 'Use one of ${SchemaType.byWire.keys.join(', ')}.',
        );
        continue;
      }
      if (known == .nullType) _context.note(.nullType, itemAt);
      types.add(known);
    }
    return List.unmodifiable(types);
  }

  Schema? _schemaAt(
    ObjectReader r,
    String key, {
    bool booleanIsClassic = false,
  }) {
    final raw = r.value(key);
    if (raw == null) return null;
    return parse(
      raw.$1,
      r.pointer.child(key),
      booleanIsClassic: booleanIsClassic,
    );
  }

  num? _bound(ObjectReader r, String key) {
    final raw = r.value(key);
    if (raw case (final num bound,)) {
      _context.note(.numericExclusiveBound, r.pointer.child(key));
      return bound;
    }
    if (raw case (bool(),)) return null;
    if (raw != null) {
      _context.report(
        .invalidValue,
        '"$key" must be a number or a boolean, not '
        '${ObjectReader.describe(raw.$1)}; it is ignored.',
        r.pointer.child(key),
      );
    }
    return null;
  }

  static bool? _flag(ObjectReader r, String key) => switch (r.value(key)) {
    (final bool flag,) => flag,
    _ => null,
  };

  Discriminator _discriminator(ObjectReader r) {
    if (r.has('defaultMapping')) {
      _context.note(.defaultMapping, r.pointer.child('defaultMapping'));
    }
    return _context.register(
      Discriminator(
        location: r.location,
        propertyName: r.requiredString('propertyName'),
        mapping: r.stringMap('mapping') ?? const {},
        defaultMapping: r.string('defaultMapping'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }
}
