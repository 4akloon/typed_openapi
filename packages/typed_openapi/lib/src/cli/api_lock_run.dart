import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/json_pointer.dart';
import '../diff/api_diff.dart';
import '../diff/change_counts.dart';
import '../ir/ir.dart';
import '../snapshot/api_lock.dart';
import '../snapshot/api_snapshot.dart';
import '../snapshot/snapshot_builder.dart';
import '../snapshot/snapshot_json.dart';

/// What one `generate` run does with `typed_openapi.lock` (M12, decisions
/// 4 and 6): it says for each client written how its API changed since the
/// lock and records the new snapshot; with `--locked` it refuses a client
/// whose API differs (TOA834) and changes no lock.
final class ApiLockRun {
  ApiLockRun._(
    this._bag,
    this._paths,
    this._path,
    this._before, {
    required this.isLocked,
  });

  /// The run for the config at [configPath]; null when its lock cannot be
  /// read (TOA835), and then no client may be written.
  static ApiLockRun? open(
    DiagnosticBag bag,
    DisplayPaths paths,
    String configPath, {
    required bool isLocked,
  }) {
    final path = ApiLock.pathFor(paths.absolute(configPath));
    final before = ApiLock(bag, paths).read(path);
    if (before == null) return null;
    return ApiLockRun._(bag, paths, path, before, isLocked: isLocked);
  }

  final DiagnosticBag _bag;
  final DisplayPaths _paths;
  final String _path;
  final Map<String, ApiSnapshot> _before;
  final _written = <String, ApiSnapshot>{};

  /// Whether the run checks against the lock instead of updating it.
  final bool isLocked;

  /// The absolute path of the lock, which no output may hold.
  String get path => _path;

  /// The snapshot of [client] with the IR [ir].
  static ApiSnapshot snapshotOf(ClientConfig client, ClientIr ir) =>
      SnapshotBuilder(SnapshotBuilder.rootOf(client)).build(ir);

  /// Whether [client] with [snapshot] may be written: always, unless the
  /// run is `--locked` and the lock has no snapshot of it or another one
  /// (TOA834).
  bool admits(String client, ApiSnapshot snapshot) {
    if (!isLocked) return true;
    final locked = _before[client];
    if (locked != null && _same(locked, snapshot)) return true;
    _differs(
      client,
      locked == null
          ? 'has no snapshot of client "$client"'
          : 'differs from the API of client "$client": '
                '${ChangeCounts(const ApiDiff().compare(locked, snapshot))}',
    );
    return false;
  }

  /// Records [snapshot] of the written [client]; returns the line that
  /// counts its changes since the lock.
  String record(String client, ApiSnapshot snapshot) {
    _written[client] = snapshot;
    final locked = _before[client];
    const lock = ApiLock.fileName;
    if (locked == null) return 'API of $client: first snapshot in $lock.';
    final counts = ChangeCounts(const ApiDiff().compare(locked, snapshot));
    return 'API of $client since $lock: $counts.';
  }

  /// Ends the run: writes the lock with the recorded snapshots, keeping
  /// those of the other clients and dropping those of clients the config
  /// no longer declares, [declared]; with `--locked` reports such a
  /// snapshot instead (TOA834) and writes nothing.
  void finish(Set<String> declared) {
    final stale = _before.keys.where((c) => !declared.contains(c)).toList()
      ..sort();
    if (isLocked) {
      for (final client in stale) {
        _differs(
          client,
          'has a snapshot of client "$client", which the '
          'config no longer declares',
        );
      }
      return;
    }
    ApiLock(_bag, _paths).write(_path, {
      for (final MapEntry(:key, :value) in _before.entries)
        if (declared.contains(key)) key: value,
      ..._written,
    });
  }

  static bool _same(ApiSnapshot a, ApiSnapshot b) =>
      const SnapshotJson().encode({'': a}) ==
      const SnapshotJson().encode({'': b});

  void _differs(String client, String problem) => _bag.report(
    .apiLockDiffers,
    '${ApiLock.fileName} $problem. Run generate without --locked and commit '
    'the lock; typed_openapi diff lists the changes.',
    file: _paths.of(_path),
    pointer: JsonPointer.root.child('clients').child(client),
  );
}
