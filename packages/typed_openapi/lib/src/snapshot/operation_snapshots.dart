import '../ir/ir.dart';
import 'api_snapshot.dart';
import 'snapshot_identities.dart';

/// The snapshot entries of the operations of a client: a group with its
/// methods, their arguments and wire facts, and the types the emitter
/// declares for a method (status types, event unions, parts classes).
final class OperationSnapshots {
  /// Creates the entries with [_ids].
  const OperationSnapshots(this._ids);

  final SnapshotIdentities _ids;

  /// The types of [group] by identity: the group, then the types of its
  /// methods.
  Map<String, SnapshotType> of(GroupIr group) => {
    'group:${group.key}': SnapshotType(
      group.name,
      .group,
      members: {
        for (final operation in group.operations) ..._method(operation),
      },
    ),
    for (final operation in group.operations) ..._typesOf(operation),
  };

  /// The method of [operation], then its parameters and its body.
  Map<String, SnapshotMember> _method(OperationIr operation) {
    final id = _ids.method(operation);
    return {
      id: SnapshotMember(
        operation.name,
        .method,
        facts: {
          'returns': 'Result<${_success(operation)}, ${_error(operation)}>',
          'method': operation.method.toUpperCase(),
          'path': operation.path,
          'accept': ?operation.accept,
          'responses': [
            for (final r in operation.responses)
              if (r.contentType case final media?)
                '${r.status} $media'
              else
                r.status,
          ].join(', '),
          'doc': ?SnapshotIdentities.doc([
            operation.summary,
            operation.description,
          ]),
          if (operation.deprecated) 'deprecated': 'true',
        },
      ),
      for (final parameter in operation.parameters)
        '$id/${parameter.name}': _parameter(parameter, id),
      '$id/body': ?_body(operation),
    };
  }

  /// The success type `T` of [operation], as the emitter writes it.
  String _success(OperationIr operation) {
    if (operation.successType case final sealed?) return sealed.name;
    if (operation.events case final events?) {
      final item = switch ((events.union, events.data)) {
        (final union?, _) => union.name,
        (null, final data?) => _ids.text(data),
        (null, null) => 'String',
      };
      return 'Stream<SseItem<$item>>';
    }
    final successes = operation.successes;
    if (successes.isEmpty) return 'JsonValue';
    return switch (successes.first.type) {
      final type? => _ids.text(type),
      null => 'void',
    };
  }

  /// The error type `E` of [operation], as the emitter writes it.
  String _error(OperationIr operation) => switch (operation.errors) {
    NoErrors() => 'Never',
    SingleError(:final type) => _ids.text(type),
    ErrorsByStatus() => operation.errorType?.name ?? 'Never',
  };

  SnapshotMember _parameter(ParameterIr parameter, String method) =>
      SnapshotMember(
        parameter.name,
        .parameter,
        owner: method,
        facts: {
          'type': _ids.text(parameter.type),
          'required': '${parameter.required}',
          'in': parameter.placement.name,
          'wire': parameter.wireName,
          'style': ?parameter.style?.name,
          'explode': ?parameter.explode?.toString(),
          if (parameter.allowReserved) 'allowReserved': 'true',
          'media': ?parameter.contentType,
          'doc': ?SnapshotIdentities.doc([parameter.description]),
          if (parameter.deprecated) 'deprecated': 'true',
        },
      );

  /// The `body` argument of [operation]; null when it takes none.
  SnapshotMember? _body(OperationIr operation) {
    final body = operation.body;
    if (body == null || body.kind == .none) return null;
    final type =
        operation.partsName ??
        switch (body.type) {
          _ when body.kind == .bytes => 'FileUpload',
          final type? => _ids.text(type),
          null => null,
        };
    if (type == null) return null;
    return SnapshotMember(
      'body',
      .body,
      owner: _ids.method(operation),
      facts: {
        'type': type,
        'required': '${body.required}',
        'kind': body.kind.name,
        'media': ?body.contentType,
      },
    );
  }

  /// The status types, the event union and the parts class of [operation].
  Map<String, SnapshotType> _typesOf(OperationIr operation) {
    final id = _ids.method(operation);
    return {
      if (operation.successType case final type?)
        '$id#success': _statusType(type),
      if (operation.errorType case final type?) '$id#error': _statusType(type),
      if (operation.events?.union case final union?)
        '$id#events': _eventUnion(union),
      if ((operation.partsName, operation.body?.parts) case (
        final name?,
        final parts?,
      ))
        '$id#parts': _parts(name, parts),
    };
  }

  SnapshotType _statusType(StatusTypeIr type) => SnapshotType(
    type.name,
    .statusType,
    exhaustive: type.exhaustive,
    members: {
      for (final variant in type.cases)
        variant.status: SnapshotMember(
          variant.name,
          .statusCase,
          facts: {
            'type': switch (variant.type) {
              final body? => _ids.text(body),
              null => 'none',
            },
          },
        ),
    },
  );

  SnapshotType _eventUnion(EventUnionIr union) => SnapshotType(
    union.name,
    .eventUnion,
    exhaustive: union.exhaustive,
    facts: {if (union.keepUnknown) 'unknown': union.unknownName},
    members: {
      for (final variant in union.variants)
        variant.event: SnapshotMember(
          variant.name,
          .event,
          facts: {
            'data': switch (variant.data) {
              final data? => _ids.text(data),
              null => variant.hasData ? 'String' : 'none',
            },
          },
        ),
    },
  );

  SnapshotType _parts(String name, List<PartIr> parts) => SnapshotType(
    name,
    .parts,
    members: {
      for (final part in parts)
        part.name: SnapshotMember(
          part.name,
          .field,
          facts: {
            'type': _ids.text(part.type),
            'required': '${part.required}',
            'json': part.wireName,
            'media': ?part.contentType,
            'doc': ?SnapshotIdentities.doc([part.description]),
          },
        ),
    },
  );
}
