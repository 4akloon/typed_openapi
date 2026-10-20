import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../ir/name_lock.dart';
import 'api_lock.dart';
import 'snapshot_builder.dart';
import 'snapshot_name_lock.dart';

/// The names `typed_openapi.lock` keeps for the clients of a config (M12,
/// decision 5), which every command that builds an IR names types and
/// methods with.
final class ApiLockNames {
  /// Creates the reader; a lock that cannot be read is reported to [_bag]
  /// (TOA835), naming files as [_paths] does.
  const ApiLockNames(this._bag, this._paths);

  final DiagnosticBag _bag;
  final DisplayPaths _paths;

  /// The names the lock next to [config] keeps, by client name; none when
  /// the file is missing or cannot be read.
  Map<String, NameLock> of(ProjectConfig config) {
    final path = ApiLock.pathFor(_paths.absolute(config.file));
    final clients = ApiLock(_bag, _paths).read(path);
    return {
      for (final client in config.clients)
        if (clients?[client.name] case final snapshot?)
          client.name: SnapshotNameLock.of(
            snapshot,
            SnapshotBuilder.rootOf(client),
          ),
    };
  }
}
