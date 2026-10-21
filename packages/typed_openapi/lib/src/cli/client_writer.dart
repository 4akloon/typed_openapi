import 'package:typed_openapi_core/typed_openapi_core.dart';
import '../emit/api_library.dart';
import '../generate/output_writer.dart';
import 'api_lock_run.dart';
import 'generation_inputs.dart';

/// Writes each client a `generate` run checked into its output directory
/// and says in one line what became of it.
final class ClientWriter {
  /// Creates a writer that writes through [_writer] and records each
  /// client's API in [_lock]; [protected] are the files no output may hold,
  /// [overlapping] the clients whose output overlaps another's, and [force]
  /// and [breakLock] the flags of the run.
  const ClientWriter(
    this._writer,
    this._paths,
    this._lock, {
    required this.protected,
    required this.overlapping,
    required this.force,
    required this.breakLock,
  });

  final OutputWriter _writer;
  final DisplayPaths _paths;
  final ApiLockRun _lock;

  /// Every file any client of the config reads, by absolute path.
  final List<String> protected;

  /// The names of the clients whose output overlaps that of another.
  final Set<String> overlapping;

  /// Whether files the generator did not write may be replaced.
  final bool force;

  /// Whether a lock that cannot be told may be taken over.
  final bool breakLock;

  /// Writes the client of [check], unless it has errors, an overlapping
  /// output or, with `--locked`, an API the lock does not have; returns the
  /// lines that say what happened.
  String write(ClientCheck check) {
    final client = check.client;
    final ir = check.ir;
    final irJson = check.irJson;
    if (ir == null || irJson == null || check.errors > 0) {
      return 'Skipped ${client.name}: its check reports errors; fix them and '
          'run generate again.';
    }
    if (overlapping.contains(client.name)) {
      return 'Skipped ${client.name}: its output overlaps the output of '
          'another client (TOA904).';
    }
    final snapshot = ApiLockRun.snapshotOf(client, ir);
    if (!_lock.admits(client.name, snapshot)) {
      return 'Skipped ${client.name}: its API differs from '
          '${ApiLock.fileName} (TOA834).';
    }
    final files = _files(client, ir);
    final changes = _writer.write(
      client,
      files,
      inputs: GenerationInputs.of(client, ir, irJson),
      protected: protected,
      force: force,
      breakLock: breakLock,
    );
    if (changes == null) return 'Skipped ${client.name}: see the error above.';
    return 'Generated ${client.name} in ${_paths.of(client.output)}: '
        '${files.length} files, ${changes.written} written, '
        '${changes.deleted} deleted.'
        '${changes.forced == 0 ? '' : ' --force replaced '
                  '${changes.forced} foreign or modified '
                  '${changes.forced == 1 ? 'file' : 'files'}.'}\n'
        '${_lock.record(client.name, snapshot)}';
  }

  /// The files of the whole client [client] with the IR [ir].
  static Map<String, String> _files(ClientConfig client, ClientIr ir) =>
      ApiLibrary(width: client.lineWidth).files(ir, client: client.name);
}
