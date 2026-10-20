import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// A fake `typed_openapi` executable and a local "releases" directory, for
/// tests of the release scripts.
final class ReleaseFixture {
  /// Creates the fake executable that prints its arguments.
  ReleaseFixture() : _temp = TempDir() {
    final executable = _temp.write(
      'typed_openapi',
      '#!/bin/sh\necho "fake typed_openapi \$@"\n',
    );
    Process.runSync('chmod', ['+x', executable]);
  }

  /// The version the fixture packs and installs.
  static const defaultVersion = '0.1.0';

  final TempDir _temp;

  static String _script(String relativePath) =>
      p.absolute('..', '..', relativePath);

  /// The directory `package.sh` writes to and `install.sh` downloads from.
  String get releaseDirectory =>
      p.join(_temp.path, 'releases', 'typed_openapi-v$defaultVersion');

  /// The `TYPED_OPENAPI_RELEASES` URL of the local releases.
  String get releasesUrl => Uri.file(p.join(_temp.path, 'releases')).toString();

  /// The directory `install.sh` extracts into.
  String get installDirectory => p.join(_temp.path, 'install');

  /// Packs the fake executable for [target] and writes `SHA256SUMS`.
  void pack(String target) {
    final result = package([
      target,
      defaultVersion,
      p.join(_temp.path, 'typed_openapi'),
      releaseDirectory,
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    final files = Directory(releaseDirectory).listSync()
      ..sort((a, b) => a.path.compareTo(b.path));
    final sums = [
      for (final file in files)
        if (file.path.endsWith('.sha256')) File(file.path).readAsStringSync(),
    ];
    File(p.join(releaseDirectory, 'SHA256SUMS')).writeAsStringSync(sums.join());
  }

  /// Runs `release/package.sh` with [arguments].
  ProcessResult package(List<String> arguments) =>
      Process.runSync(_script('release/package.sh'), arguments);

  /// Runs `action/install.sh` for the runner [os] and [arch].
  ProcessResult install(
    String os,
    String arch, {
    String version = defaultVersion,
  }) => Process.runSync(
    _script('action/install.sh'),
    [version, os, arch, installDirectory],
    environment: {'TYPED_OPENAPI_RELEASES': releasesUrl},
  );

  /// Runs `action/run.sh` with the action [inputs] as `INPUT_*` variables.
  ProcessResult run(Map<String, String> inputs) => Process.runSync(
    _script('action/run.sh'),
    [],
    environment: {
      'INPUT_EXECUTABLE': p.join(_temp.path, 'typed_openapi'),
      'INPUT_FORMAT': 'text',
      ...inputs,
    },
  );
}
