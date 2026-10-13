import 'dart:convert';
import 'dart:io';

import 'process_runner.dart';

/// What a lock file says about the run that holds it.
final class LockHolder {
  /// Reads the content of a lock file; the process stays unknown for an
  /// empty or foreign file.
  factory LockHolder(String text) {
    try {
      if (jsonDecode(text) case {
        'pid': final int processId,
        'host': final String host,
      }) {
        return LockHolder._(text, processId, host);
      }
    } on FormatException {
      // An empty or foreign file: the process stays unknown.
    }
    return LockHolder._(text, null, null);
  }

  LockHolder._(this.text, this.processId, this.host);

  /// What the lock [file] says, or null when it is gone.
  static LockHolder? read(File file) {
    try {
      return LockHolder(file.readAsStringSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      return LockHolder('');
    }
  }

  /// The content of the lock file.
  final String text;

  /// The process id it names, or null.
  final int? processId;

  /// The host it names, or null.
  final String? host;

  /// The holder, as a message says it.
  String get describe => processId == null
      ? 'a lock file typed_openapi did not write'
      : 'process $processId on $host';

  /// Whether the process that wrote the lock still runs: true or false when
  /// that can be told, null when it cannot (another host, no readable pid, a
  /// system with no `kill`).
  bool? isAlive(ProcessRunner run) {
    final process = processId;
    if (process == null || host != Platform.localHostname) return null;
    if (process == pid) return true;
    if (Platform.isWindows) return null;
    try {
      final result = run('kill', ['-0', '$process']);
      if (result.exitCode == 0) return true;
      return '${result.stderr}'.contains('No such process') ? false : null;
    } on ProcessException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is LockHolder && other.text == text;

  @override
  int get hashCode => text.hashCode;
}
