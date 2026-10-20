import 'dart:convert';

import '../ir/ir.dart';
import 'api_snapshot.dart';
import 'snapshot_identities.dart';

/// The snapshot entries of the declarations of a client: models, enums and
/// unions, with their fields, values and variants.
final class DeclarationSnapshots {
  /// Creates the entries with [_ids].
  const DeclarationSnapshots(this._ids);

  final SnapshotIdentities _ids;

  /// The type of [declaration].
  SnapshotType of(Declaration declaration) => switch (declaration) {
    ModelDecl() => _model(declaration),
    EnumDecl() => _enum(declaration),
    UnionDecl() => _union(declaration),
  };

  /// The facts every declaration has: its documentation.
  static Map<String, String> _common(Declaration declaration) => {
    'doc': ?SnapshotIdentities.doc([declaration.description]),
    if (declaration.deprecated) 'deprecated': 'true',
  };

  SnapshotType _model(ModelDecl model) => SnapshotType(
    model.name,
    .model,
    facts: {
      ..._common(model),
      if (model.additionalProperties case final additional?) ...{
        'additional': _ids.text(additional),
        'additionalName': model.additionalPropertiesName,
      },
    },
    members: {for (final field in model.fields) field.name: _field(field)},
  );

  SnapshotMember _field(FieldIr field) => SnapshotMember(
    field.name,
    .field,
    facts: {
      'type': _ids.text(field.type),
      'required': '${field.required}',
      'json': field.jsonKey,
      if (field.constValue case final value?) 'const': jsonEncode(value),
      'doc': ?SnapshotIdentities.doc([field.description]),
      if (field.deprecated) 'deprecated': 'true',
    },
  );

  SnapshotType _enum(EnumDecl decl) => SnapshotType(
    decl.name,
    .enumeration,
    exhaustive: decl.exhaustive,
    facts: {
      ..._common(decl),
      'kind': decl.kind.name,
      'known': decl.knownName,
      'unknown': decl.unknownName,
    },
    members: {
      for (final value in decl.values)
        jsonEncode(value.value): SnapshotMember(
          value.name,
          .value,
          facts: {
            'doc': ?SnapshotIdentities.doc([value.description]),
          },
        ),
    },
  );

  SnapshotType _union(UnionDecl decl) => SnapshotType(
    decl.name,
    .union,
    exhaustive: decl.exhaustive,
    facts: {
      ..._common(decl),
      'discriminator': ?decl.discriminator,
      'unknown': decl.unknownName,
    },
    members: {
      for (final variant in decl.variants)
        'variant:${_ids.key(variant.type)}': SnapshotMember(
          variant.name,
          .variant,
          facts: {
            'type': _ids.text(variant.type),
            if (variant.discriminatorValues.isNotEmpty)
              'values': variant.discriminatorValues.join(', '),
          },
        ),
    },
  );
}
