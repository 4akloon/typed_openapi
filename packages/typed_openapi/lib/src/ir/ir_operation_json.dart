import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';

/// Writes the operations of a [ClientIr], the root client and the types the
/// API emitter reads as plain JSON values (the part of [IrJson] that is
/// about operations).
///
/// Optional keys are left out when they have no value, so the output stays
/// as short as the IR allows.
final class IrOperationJson {
  /// Creates a writer; [_at] writes a location and [_type] a Dart type.
  const IrOperationJson(this._at, this._type);

  final String Function(SpecLocation) _at;
  final String Function(DartType) _type;

  /// The root client: its class and its servers.
  Map<String, Object?> root(RootIr root) => {
    'name': root.name,
    'servers': [
      for (final server in root.servers)
        {
          'name': server.name,
          'url': server.url,
          'at': _at(server.location),
          'description': ?server.description,
          'variables': [
            for (final v in server.variables)
              {
                'name': v.name,
                'wire': v.wireName,
                'default': ?v.defaultValue,
                'values': v.values,
                'description': ?v.description,
              },
          ],
        },
    ],
  };

  /// [o] with everything the IR knows about it.
  Map<String, Object?> operation(OperationIr o) => {
    'name': o.name,
    'method': o.method,
    'path': o.path,
    'at': _at(o.location),
    'parameters': [for (final p in o.parameters) _parameter(p)],
    if (o.body case final body?) 'body': _body(body),
    'responses': [for (final r in o.responses) _response(r)],
    ..._errors(o.errors),
    'operationId': ?o.operationId,
    if (o.tags.isNotEmpty) 'tags': o.tags,
    'summary': ?o.summary,
    'description': ?o.description,
    if (o.deprecated) 'deprecated': true,
    if (o.security.isNotEmpty)
      'security': [
        for (final alternative in o.security)
          [for (final use in alternative) _securityUse(use)],
      ],
    if (o.successType case final type?) 'successType': _statusType(type),
    if (o.errorType case final type?) 'errorType': _statusType(type),
    'partsName': ?o.partsName,
    'accept': ?o.accept,
    if (o.events case final events?) 'events': _events(events),
  };

  Map<String, Object?> _events(EventStreamIr events) => {
    if (events.data case final data?) 'data': _type(data),
    if (events.union case final union?) 'union': _union(union),
    'reconnection': events.reconnection.name,
  };

  /// The `errors` entry of an operation and the keys that go with it.
  Map<String, Object?> _errors(ErrorsIr errors) => {
    'errors': switch (errors) {
      NoErrors() => 'Never',
      SingleError(:final type) => _type(type),
      ErrorsByStatus(:final cases) => {
        for (final (status, t) in cases) status: t == null ? null : _type(t),
      },
    },
    'errorStatuses': ?switch (errors) {
      SingleError(:final statuses) when statuses.isNotEmpty => statuses,
      _ => null,
    },
    'sensitiveErrors': ?switch (errors) {
      ErrorsByStatus(:final sensitive) when sensitive.isNotEmpty =>
        sensitive.toList()..sort(),
      _ => null,
    },
  };

  Map<String, Object?> _union(EventUnionIr union) => {
    'name': union.name,
    'at': _at(union.location),
    if (union.keepUnknown) 'unknownName': union.unknownName,
    'keepUnknown': union.keepUnknown,
    if (union.unknownSensitive) 'unknownSensitive': true,
    'variants': [
      for (final v in union.variants)
        {
          'event': v.event,
          'name': v.name,
          'hasData': v.hasData,
          if (v.data case final data?) 'data': _type(data),
          if (v.sensitive) 'sensitive': true,
        },
    ],
  };

  Map<String, Object?> _parameter(ParameterIr p) => {
    'name': p.name,
    'in': p.placement.name,
    'wire': p.wireName,
    'type': _type(p.type),
    if (p.required) 'required': true,
    'style': ?p.style?.name,
    'explode': ?p.explode,
    if (p.allowReserved) 'allowReserved': true,
    'contentType': ?p.contentType,
    if (p.defaultValue case (final value,)) 'default': value,
    'description': ?p.description,
    if (p.deprecated) 'deprecated': true,
  };

  Map<String, Object?> _body(RequestBodyIr body) => {
    'kind': body.kind.name,
    'contentType': ?body.contentType,
    if (body.type case final t?) 'type': _type(t),
    if (body.required) 'required': true,
    'description': ?body.description,
    if (body.encoding.isNotEmpty)
      'encoding': [
        for (final e in body.encoding)
          {
            'property': e.property,
            'contentType': ?e.contentType,
            'style': ?e.style?.name,
            'explode': ?e.explode,
            if (e.allowReserved) 'allowReserved': true,
          },
      ],
    if (body.parts case final parts?)
      'parts': [
        for (final part in parts)
          {
            'name': part.name,
            'wire': part.wireName,
            'type': _type(part.type),
            if (part.required) 'required': true,
            'at': _at(part.location),
            'contentType': ?part.contentType,
            'description': ?part.description,
          },
      ],
  };

  Map<String, Object?> _response(ResponseIr r) => {
    'status': r.status,
    'kind': r.kind.name,
    if (r.type case final t?) 'type': _type(t),
    'envelope': ?r.envelopeKey,
    if (r.sensitive) 'sensitive': true,
  };

  Map<String, Object?> _statusType(StatusTypeIr type) => {
    'name': type.name,
    'cases': [
      for (final c in type.cases)
        {
          'status': c.status,
          'name': c.name,
          if (c.type case final t?) 'type': _type(t),
          if (c.sensitive) 'sensitive': true,
        },
    ],
  };

  Map<String, Object?> _securityUse(SecurityUseIr use) => {
    'scheme': {
      'name': use.scheme.name,
      'kind': use.scheme.kind.name,
      'parameterName': ?use.scheme.parameterName,
      'placement': ?use.scheme.placement,
      'scheme': ?use.scheme.scheme,
      'bearerFormat': ?use.scheme.bearerFormat,
      'openIdConnectUrl': ?use.scheme.openIdConnectUrl,
    },
    'scopes': use.scopes,
  };
}
