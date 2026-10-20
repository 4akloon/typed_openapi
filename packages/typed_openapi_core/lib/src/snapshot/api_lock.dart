import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'api_snapshot.dart';
import 'snapshot_json.dart';

/// Reads and writes `typed_openapi.lock`, the API snapshot of every client
/// next to the config (M12, decision 6). A problem with the file is
/// TOA835.
final class ApiLock {
  /// Creates the reader; problems go to [_bag], files are named as
  /// [_paths] does.
  const ApiLock(this._bag, this._paths);

  final DiagnosticBag _bag;
  final DisplayPaths _paths;

  /// The name of the lock file.
  static const fileName = 'typed_openapi.lock';

  static const _json = SnapshotJson();

  /// The path of the lock of the config at [configPath].
  static String pathFor(String configPath) =>
      p.join(p.dirname(configPath), fileName);

  /// The snapshots of the lock at [path] by client: empty when there is no
  /// file, null (with TOA835) when it cannot be read or is not a lock.
  Map<String, ApiSnapshot>? read(String path) {
    final file = File(path);
    if (!file.existsSync()) return const {};
    try {
      return _json.decode(file.readAsStringSync());
    } on FileSystemException catch (e) {
      _report(path, 'cannot be read: ${e.message}');
    } on FormatException catch (e) {
      _report(path, 'is not an API lock of version 1: ${e.message}');
    }
    return null;
  }

  /// Writes [clients] to [path] through a temporary file in the same
  /// directory, so an interrupted write never leaves a broken lock, unless
  /// the file holds that text already.
  void write(String path, Map<String, ApiSnapshot> clients) {
    final text = _json.encode(clients);
    final target = File(path);
    final temp = File('$path.tmp');
    try {
      if (target.existsSync() && target.readAsStringSync() == text) return;
      temp.writeAsStringSync(text);
      temp.renameSync(path);
    } on FileSystemException catch (e) {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // Nothing more can be done about a leftover temporary file.
      }
      _report(path, 'cannot be written: ${e.message}');
    }
  }

  void _report(String path, String problem) => _bag.report(
    .apiLockUnusable,
    '${_paths.of(path)} $problem. Fix or delete the file and run generate '
    'again.',
    file: _paths.of(path),
  );
}
