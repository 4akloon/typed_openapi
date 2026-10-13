import 'package:typed_openapi/typed_openapi.dart';

import 'sample.dart';

/// JSON values built from the IR of a client (spec decision 3): for each
/// model one with its required fields and one with every field, for each
/// enum its first and last value, for each union one value of each variant
/// (with its discriminator value).
///
/// A value is a record `(json,)`, so that JSON `null` is a value; null means
/// that no value can be built (a custom type, or nesting deeper than
/// [maxDepth] in a required field).
final class SyntheticValues {
  /// Creates the values of the client [ir].
  SyntheticValues(this._ir)
    : _byId = {for (final d in _ir.declarations) d.id: d};

  /// How deep declarations nest in one value.
  static const int maxDepth = 6;

  final ClientIr _ir;
  final Map<DeclId, Declaration> _byId;

  /// The values of every declaration.
  List<Sample> all() => [
    for (final d in _ir.declarations)
      for (final (value,) in _valuesOf(d))
        Sample(d.name, value, isExample: false),
  ];

  /// How many values [all] tries to build: the number it returns plus the
  /// ones no value could be built for (a custom type, or nesting too deep).
  int get attempted => _ir.declarations.fold(0, (n, d) => n + _attempts(d));

  static int _attempts(Declaration d) => switch (d) {
    ModelDecl() => 2,
    EnumDecl(:final values) => values.length.clamp(0, 2),
    UnionDecl(:final variants) => variants.length,
  };

  List<(Object?,)> _valuesOf(Declaration d) => switch (d) {
    ModelDecl() => [?_model(d, 0, every: false), ?_model(d, 0, every: true)],
    EnumDecl(:final values) when values.isEmpty => const [],
    EnumDecl(:final values) => [
      (values.first.value,),
      if (values.length > 1) (values.last.value,),
    ],
    UnionDecl(:final variants) => [
      for (final variant in variants) ?_variant(d, variant, 0),
    ],
  };

  (Object?,)? _model(ModelDecl model, int depth, {required bool every}) {
    final json = <String, Object?>{};
    for (final field in model.fields) {
      if (!field.required && !every) continue;
      final value = switch (field.constValue) {
        final constant? => (constant,),
        null => _value(field.valueType, depth + 1),
      };
      if (value == null) {
        if (field.required) return null;
        continue;
      }
      json[field.jsonKey] = value.$1;
    }
    final additional = every ? model.additionalProperties : null;
    if (additional != null) {
      if (_value(additional, depth + 1) case (final extra,)) {
        json['__extra'] = extra;
      }
    }
    return (json,);
  }

  (Object?,)? _variant(UnionDecl union, UnionVariantIr variant, int depth) {
    if (variant.jsonKinds.isNotEmpty) {
      return (
        switch (variant.jsonKinds.first) {
          .string => 'text',
          .integer => 1,
          .number => 2.5,
          .boolean => true,
          .array => <Object?>[],
          .object => <String, Object?>{},
        },
      );
    }
    final value = _value(variant.type, depth + 1);
    final property = union.discriminator;
    if (property == null || value == null) return value;
    if (variant.discriminatorValues.isEmpty) return null;
    return switch (value.$1) {
      final Map<String, Object?> object => (
        {...object, property: variant.discriminatorValues.first},
      ),
      _ => value,
    };
  }

  (Object?,)? _value(DartType type, int depth) {
    if (depth > maxDepth) return null;
    return switch (type) {
      CoreType(:final kind) => _core(kind),
      ListType(:final item) => ([?_value(item, depth + 1)?.$1],),
      MapType(:final value) => switch (_value(value, depth + 1)) {
        (final v,) => ({'key': v},),
        null => (<String, Object?>{},),
      },
      NamedType(:final id) => switch (_byId[id]) {
        final ModelDecl model => _model(model, depth, every: false),
        EnumDecl(:final values) when values.isNotEmpty => (values.first.value,),
        final UnionDecl union => _firstVariant(union, depth),
        _ => null,
      },
      PatchType(:final value) => _value(value, depth),
      CustomType() => null,
    };
  }

  (Object?,)? _firstVariant(UnionDecl union, int depth) {
    for (final variant in union.variants) {
      if (_variant(union, variant, depth) case final value?) return value;
    }
    return null;
  }

  static (Object?,)? _core(CoreKind kind) => switch (kind) {
    .integer => (1,),
    .float => (1.5,),
    .number => (2.5,),
    .string => ('text',),
    .boolean => (true,),
    .dateTime => ('2026-01-02T03:04:05.000Z',),
    .date => ('2026-01-02',),
    .bytes => ('AQID',),
    .binary => null,
    .json => (
      {
        'any': [1, 'two'],
      },
    ),
  };
}
