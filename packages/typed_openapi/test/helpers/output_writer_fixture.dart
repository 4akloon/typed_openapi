import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/src/generate/output_writer.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// A client whose output is `gen/pets` in a temp directory, and an
/// [OutputWriter] run on it, for the tests of the writer.
final class OutputWriterFixture {
  /// Creates the temp directory (deleted after the current test), the client
  /// and an empty bag.
  OutputWriterFixture() : this._(TempDir());

  OutputWriterFixture._(this.dir)
    : bag = DiagnosticBag(),
      client = ClientConfig(
        name: 'pets',
        input: p.join(dir.path, 'spec.yaml'),
        output: p.join(dir.path, 'gen', 'pets'),
        lineWidth: 80,
      );

  /// The temp directory that holds the client's files.
  final TempDir dir;

  /// Where the writer reports; a test may put a new bag in to look at one
  /// run alone.
  DiagnosticBag bag;

  /// The client that the writer writes the output of.
  final ClientConfig client;

  /// Writes [files] to the output of [client] with a writer made for tests,
  /// whose [beforeInstall] and [run] hooks are the ones given.
  OutputChanges? write(
    Map<String, String> files, {
    List<String> protected = const [],
    void Function()? beforeInstall,
    bool force = false,
    bool breakLock = false,
    ProcessResult Function(String, List<String>)? run,
  }) => OutputWriter.forTesting(bag, beforeInstall: beforeInstall, run: run)
      .write(
        client,
        files,
        inputs: 'in',
        protected: protected,
        force: force,
        breakLock: breakLock,
      );

  /// Every entry under the temp directory, sorted, with file content.
  Map<String, String?> everything() => {
    for (final e
        in dir.directory.listSync(recursive: true, followLinks: false).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      p.posix.joinAll(p.split(p.relative(e.path, from: dir.path))): e is File
          ? e.readAsStringSync()
          : null,
  };
}
