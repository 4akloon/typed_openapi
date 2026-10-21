import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';

/// Writes the declarations of a [ClientIr] (models, enums and unions) for
/// [IrJson]: every field an emitter reads, locations aside.
final class IrDeclarationJson {
  /// Creates a writer; [_at] writes a location or gives null and [_type]
  /// writes a Dart type.
  const IrDeclarationJson(this._at, this._type);

  final String? Function(SpecLocation) _at;
  final String Function(DartType) _type;

  /// [d] as plain JSON values.
  Map<String, Object?> declaration(Declaration d) => {
    'name': d.name,
    'at': ?_at(d.location),
    if (d.id.variant != .base) 'variant': d.id.variant.name,
    'description': ?d.description,
    if (d.deprecated) 'deprecated': true,
    ...switch (d) {
      ModelDecl() => _model(d),
      EnumDecl() => _enum(d),
      UnionDecl() => _union(d),
    },
  };

  Map<String, Object?> _model(ModelDecl d) => {
    'kind': 'model',
    if (d.direction != .both) 'direction': d.direction.name,
    'fields': [for (final f in d.fields) _field(f)],
    if (d.additionalProperties case final extra?) ...{
      'additionalProperties': _type(extra),
      'additionalPropertiesName': d.additionalPropertiesName,
    },
    if (d.additionalSensitive) 'additionalSensitive': true,
  };

  Map<String, Object?> _field(FieldIr f) => {
    'name': f.name,
    'json': f.jsonKey,
    'type': _type(f.type),
    if (f.required) 'required': true,
    if (f.triState) 'triState': true,
    if (f.readOnly) 'readOnly': true,
    if (f.writeOnly) 'writeOnly': true,
    if (f.sensitive) 'sensitive': true,
    if (f.defaultValue case (final value,)) 'default': value,
    'description': ?f.description,
    if (f.deprecated) 'deprecated': true,
    'constValue': ?f.constValue,
    if (!f.constraints.isEmpty) 'constraints': _constraints(f.constraints),
    if (f.knownValues.isNotEmpty) 'knownValues': f.knownValues,
  };

  Map<String, Object?> _constraints(ConstraintsIr c) => {
    'minLength': ?c.minLength,
    'maxLength': ?c.maxLength,
    'pattern': ?c.pattern,
    'minimum': ?c.minimum,
    'maximum': ?c.maximum,
    'exclusiveMinimum': ?c.exclusiveMinimum,
    'exclusiveMaximum': ?c.exclusiveMaximum,
    'multipleOf': ?c.multipleOf,
    'minItems': ?c.minItems,
    'maxItems': ?c.maxItems,
    if (c.uniqueItems) 'uniqueItems': true,
    'minProperties': ?c.minProperties,
    'maxProperties': ?c.maxProperties,
  };

  Map<String, Object?> _enum(EnumDecl d) => {
    'kind': 'enum',
    'values': d.kind.name,
    if (!d.exhaustive) 'exhaustive': false,
    'knownName': d.knownName,
    'unknownName': d.unknownName,
    'cases': [
      for (final v in d.values)
        {'name': v.name, 'value': v.value, 'description': ?v.description},
    ],
  };

  Map<String, Object?> _union(UnionDecl d) => {
    'kind': d.kind.name,
    'dispatch': d.dispatch.name,
    'discriminator': ?d.discriminator,
    if (!d.exhaustive) 'exhaustive': false,
    'unknownName': d.unknownName,
    'variants': [
      for (final v in d.variants)
        {
          'type': _type(v.type),
          'name': v.name,
          if (v.jsonKinds.isNotEmpty)
            'jsonKinds': [for (final kind in v.jsonKinds) kind.name],
          if (v.discriminatorValues.isNotEmpty) 'values': v.discriminatorValues,
          if (v.sensitive) 'sensitive': true,
        },
    ],
    if (d.defaultVariant case final variant?) 'default': _type(variant),
    if (d.unknownSensitive) 'unknownSensitive': true,
  };
}
