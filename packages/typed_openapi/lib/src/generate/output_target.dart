import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:typed_openapi_core/typed_openapi_core.dart';

/// The output of a run: the client's directory, and the input files of the
/// run that it must not hold.
final class OutputTarget {
  /// Creates the output of [client] and the [inputs] of the run.
  OutputTarget(this.client, this.inputs)
    : root = p.normalize(p.absolute(client.output));

  /// The client whose output this is.
  final ClientConfig client;

  /// The output directory, absolute and normalized.
  final String root;

  /// The input files of the run (the config, the spec, the overrides, the
  /// baseline), which may not exist.
  final List<String> inputs;

  /// The directory that holds the output, where the lock, the temporary tree
  /// and the backup live.
  Directory get parent => Directory(p.dirname(root));

  /// The [inputs] that exist.
  List<String> get presentInputs => [
    for (final input in inputs)
      if (File(input).existsSync()) input,
  ];
}
