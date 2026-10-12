import 'dart:convert';

import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';

/// Writes a [ClientIr] as JSON, to inspect what the generator will emit.
///
/// The output is deterministic: keys come in a fixed order and lists in the
/// IR's order. Locations are written as `file#pointer`, with files named by
/// the function given to the constructor.
final class IrJson {
  /// Creates a writer that names documents with [_fileOf].
  const IrJson(this._fileOf);

  final String Function(Uri document) _fileOf;

  /// [ir] as indented JSON text.
  String encode(ClientIr ir) =>
      const JsonEncoder.withIndent('  ').convert(toJson(ir));

  /// [ir] as plain JSON values.
  Map<String, Object?> toJson(ClientIr ir) {
    String type(DartType t) => t.code(ir.nameOf);
    return {
      'declarations': [
        for (final d in ir.declarations) _declaration(d, type),
      ],
      'groups': [
        for (final group in ir.groups)
          {
            'name': group.name,
            'operations': [
              for (final operation in group.operations)
                _operation(operation, type),
            ],
          },
      ],
    };
  }

  String _at(SpecLocation location) =>
      '${_fileOf(location.document)}${location.pointer.value}';

  Map<String, Object?> _declaration(
    Declaration d,
    String Function(DartType) type,
  ) => {
    'name': d.name,
    'at': _at(d.location),
    if (d.deprecated) 'deprecated': true,
    ...switch (d) {
      ModelDecl() => {
        'kind': 'model',
        if (d.id.variant != .base) 'variant': d.id.variant.name,
        if (d.direction != .both) 'direction': d.direction.name,
        'fields': [
          for (final f in d.fields)
            {
              'name': f.name,
              'json': f.jsonKey,
              'type': type(f.type),
              if (f.required) 'required': true,
              if (f.triState) 'triState': true,
              if (f.readOnly) 'readOnly': true,
              if (f.writeOnly) 'writeOnly': true,
            },
        ],
        if (d.additionalProperties case final extra?)
          'additionalProperties': type(extra),
      },
      EnumDecl() => {
        'kind': 'enum',
        'values': d.kind.name,
        if (!d.exhaustive) 'exhaustive': false,
        'cases': {for (final v in d.values) v.name: v.value},
      },
      UnionDecl() => {
        'kind': d.kind.name,
        'discriminator': ?d.discriminator,
        if (!d.exhaustive) 'exhaustive': false,
        'variants': [
          for (final v in d.variants)
            {
              'type': type(v.type),
              if (v.discriminatorValues.isNotEmpty)
                'values': v.discriminatorValues,
            },
        ],
        if (d.defaultVariant case final variant?) 'default': type(variant),
      },
    },
  };

  Map<String, Object?> _operation(
    OperationIr o,
    String Function(DartType) type,
  ) => {
    'name': o.name,
    'method': o.method,
    'path': o.path,
    'at': _at(o.location),
    'parameters': [
      for (final p in o.parameters)
        {
          'name': p.name,
          'in': p.placement.name,
          'wire': p.wireName,
          'type': type(p.type),
          if (p.required) 'required': true,
        },
    ],
    if (o.body case final body?)
      'body': {
        'kind': body.kind.name,
        'contentType': ?body.contentType,
        if (body.type case final t?) 'type': type(t),
        if (body.required) 'required': true,
      },
    'responses': [
      for (final r in o.responses)
        {
          'status': r.status,
          'kind': r.kind.name,
          if (r.type case final t?) 'type': type(t),
          'envelope': ?r.envelopeKey,
          if (r.sensitive) 'sensitive': true,
        },
    ],
    'errors': switch (o.errors) {
      NoErrors() => 'Never',
      SingleError(type: final t) => type(t),
      ErrorsByStatus(:final cases) => {
        for (final (status, t) in cases) status: t == null ? null : type(t),
      },
    },
  };
}
