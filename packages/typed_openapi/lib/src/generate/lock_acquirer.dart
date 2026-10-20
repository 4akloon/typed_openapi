import 'dart:io';

import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'lock_holder.dart';
import 'output_lock.dart';
import 'output_target.dart';
import 'process_runner.dart';

/// Takes the lock of an output.
final class LockAcquirer {
  /// Creates an acquirer that reports to the bag, names paths with the
  /// display paths and starts `kill` with the runner.
  LockAcquirer(this._diagnostics, this._paths, this._run);

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final ProcessRunner _run;

  /// Takes the lock of [target] by creating its file exclusively, and returns
  /// it; null after reporting TOA831 when another run holds it. A lock of a
  /// process that is gone (it is on this host and no longer exists) is taken
  /// over with TOA832, and so is one whose owner cannot be told when
  /// [breakLock] is set; a lock of a process that runs stays held.
  OutputLock? acquire(OutputTarget target, {required bool breakLock}) {
    final file = OutputLock.fileOf(target.root);
    final lock = OutputLock(file);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        lock.create();
        return lock;
      } on PathExistsException {
        final held = LockHolder.read(file);
        if (held == null) continue; // Released in the meantime.
        final alive = held.isAlive(_run);
        if (alive == true || (alive == null && !breakLock)) {
          _reportHeld(target, file, held, knownAlive: alive == true);
          return null;
        }
        _takeOver(target, file, held, alive: alive);
      }
    }
    _reportKeepsComingBack(target, file);
    return null;
  }

  void _takeOver(
    OutputTarget target,
    File file,
    LockHolder held, {
    required bool? alive,
  }) {
    // Another process may have replaced it since: delete only what was
    // looked at.
    if (LockHolder.read(file) == held) file.deleteSync();
    _diagnostics.report(
      .outputRecovered,
      'Took over the lock ${_paths.of(file.path)} of client '
      '"${target.client.name}", ${alive == false ? 'which ${held.describe} had '
                'left behind: that process is gone' : 'which ${held.describe} '
                'held: --break-lock takes it over'}.',
      file: _paths.of(target.root),
    );
  }

  void _reportHeld(
    OutputTarget target,
    File file,
    LockHolder held, {
    required bool knownAlive,
  }) {
    _diagnostics.report(
      .outputNotWritten,
      'Client "${target.client.name}" is not generated: another typed_openapi '
      'run holds the lock ${_paths.of(file.path)} of its output '
      '${_paths.of(target.root)} (${held.describe}'
      '${knownAlive ? ', which is running' : '; it cannot be told whether '
                'that process still runs'}). Nothing was changed.',
      file: _paths.of(target.root),
      fix: knownAlive
          ? 'Wait for it to finish. If you are sure no run is going, delete '
                '${_paths.of(file.path)}.'
          : 'Delete ${_paths.of(file.path)} if no run is going, or run '
                'generate --break-lock, which takes the lock over and '
                'replaces no file.',
    );
  }

  void _reportKeepsComingBack(OutputTarget target, File file) {
    _diagnostics.report(
      .outputNotWritten,
      'Cannot take the lock ${_paths.of(file.path)} of client '
      '"${target.client.name}": it keeps coming back.',
      file: _paths.of(target.root),
      fix: 'Check whether another generate runs on this output.',
    );
  }
}
