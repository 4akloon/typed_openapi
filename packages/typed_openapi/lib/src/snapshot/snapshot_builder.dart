import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../ir/ir.dart';
import 'api_snapshot.dart';
import 'declaration_snapshots.dart';
import 'operation_snapshots.dart';
import 'snapshot_identities.dart';

/// Builds the [ApiSnapshot] of a client from its IR (M12, decision 1): the
/// emitters' only input, so the snapshot is what the generated code
/// declares, without reading that code.
final class SnapshotBuilder {
  /// Creates a builder for a spec whose root document is [_root].
  const SnapshotBuilder(this._root);

  final Uri _root;

  /// The URI of [client]'s root document as `SpecLoader` makes it, so the
  /// locations in it are relative to its directory.
  static Uri rootOf(ClientConfig client) => p.toUri(p.normalize(client.input));

  /// The snapshot of [ir], its types sorted by identity.
  ApiSnapshot build(ClientIr ir) {
    final ids = SnapshotIdentities(ir, _root);
    final declarations = DeclarationSnapshots(ids);
    final operations = OperationSnapshots(ids);
    final types = {
      for (final declaration in ir.declarations)
        ids.declaration(declaration.id): declarations.of(declaration),
      for (final group in ir.groups) ...operations.of(group),
      'root': _rootType(ir),
    };
    return ApiSnapshot({
      for (final id in types.keys.toList()..sort()) id: types[id]!,
    });
  }

  /// The root client: a field per group and the servers.
  static SnapshotType _rootType(ClientIr ir) => SnapshotType(
    ir.root.name,
    .root,
    members: {
      for (final group in ir.groups)
        'group:${group.key}': SnapshotMember(
          group.field,
          .groupField,
          facts: {'type': group.name},
        ),
      for (final (index, server) in ir.root.servers.indexed)
        'server:$index': SnapshotMember(
          server.name,
          .server,
          facts: {
            'url': server.url,
            if (server.variables.isNotEmpty)
              'variables': [
                for (final v in server.variables)
                  if (v.defaultValue == null) v.name else '${v.name}?',
              ].join(', '),
            'doc': ?SnapshotIdentities.doc([server.description]),
          },
        ),
    },
  );
}
