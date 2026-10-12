import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';

/// What [OutputWriter.write] did to an output directory.
final class OutputChanges {
  /// Creates the counts.
  const OutputChanges({
    required this.written,
    required this.unchanged,
    required this.deleted,
  });

  /// Files written because they are new or their content changed.
  final int written;

  /// Files whose content was already the generated one.
  final int unchanged;

  /// Files deleted because the generator no longer writes them.
  final int deleted;
}

/// Writes the generated files of a client into its output directory, which
/// the generator owns (decisions 15 and 17 of M8).
///
/// A file is written only when its content changes, through a temporary
/// file that is renamed over it, so a reader never sees half a file; every
/// file the generator did not write this time is deleted, and so are
/// directories left empty. The manifest [manifest] lists the generator, a
/// hash of the inputs and every file with its hash; it is written last.
///
/// The directory is refused (TOA830, nothing is written) when it holds a
/// `pubspec.yaml`, is the `lib` directory of a package, holds an input of
/// the run (the config, the spec, the overrides or the baseline file), or
/// holds files but no manifest: files the generator did not write.
final class OutputWriter {
  /// Creates a writer that reports to [_diagnostics]; [_paths] names
  /// directories in diagnostics.
  const OutputWriter(this._diagnostics, [this._paths = const DisplayPaths()]);

  /// The name of the manifest in the output directory.
  static const manifest = '.typed_openapi.json';

  /// The generator and its version, as the manifest names them.
  static const generator = 'typed_openapi 0.0.1';

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// Writes [files] (paths relative to the output directory of [client])
  /// and the manifest with [inputs], the hash of what they were generated
  /// from; [protected] are the input files of the run, which the directory
  /// must not hold. Returns null after reporting why nothing, or not
  /// everything, was written.
  OutputChanges? write(
    ClientConfig client,
    Map<String, String> files, {
    required String inputs,
    List<String> protected = const [],
  }) {
    final root = p.normalize(p.absolute(client.output));
    if (!_owned(client, root, protected)) return null;
    final sorted = files.keys.toList()..sort();
    var written = 0;
    var unchanged = 0;
    var deleted = 0;
    try {
      for (final path in sorted) {
        if (_writeFile(p.join(root, path), files[path]!)) {
          written++;
        } else {
          unchanged++;
        }
      }
      final keep = {
        ...sorted.map((f) => p.join(root, f)),
        p.join(root, manifest),
      };
      final directory = Directory(root);
      final entries = directory.listSync(recursive: true, followLinks: false)
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final entry in entries) {
        if (entry is Directory) {
          if (entry.listSync().isEmpty) entry.deleteSync();
        } else if (!keep.contains(entry.path)) {
          entry.deleteSync();
          deleted++;
        }
      }
      _writeFile(p.join(root, manifest), manifestOf(files, inputs: inputs));
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .outputNotWritten,
        'Cannot write the output of client "${client.name}" to '
        '${_paths.of(root)}: ${e.message}${e.path == null ? '' : ' (${_paths.of(e.path!)})'}.',
        file: _paths.of(root),
        fix:
            'Check that the directory can be written, then run generate '
            'again.',
      );
      return null;
    }
    return OutputChanges(
      written: written,
      unchanged: unchanged,
      deleted: deleted,
    );
  }

  /// The manifest of [files] generated from [inputs]: JSON with sorted
  /// keys, the same for the same files.
  static String manifestOf(
    Map<String, String> files, {
    required String inputs,
  }) {
    final hashes = {
      for (final path in files.keys.toList()..sort())
        path: sha256.convert(utf8.encode(files[path]!)).toString(),
    };
    return '${const JsonEncoder.withIndent('  ').convert({
      'generator': generator,
      'inputs': inputs,
      'files': hashes,
    })}\n';
  }

  /// Whether the generator may own [root]; reports why not.
  bool _owned(ClientConfig client, String root, List<String> protected) {
    void refuse(String why, String fix) => _diagnostics.report(
      .outputNotOwned,
      'Client "${client.name}" is not generated: its output directory '
      '${_paths.of(root)} $why. The generator deletes every file there it '
      'did not write.',
      file: _paths.of(root),
      fix: fix,
    );
    const move =
        'Point output to a directory of its own, such as '
        'lib/src/<client>.';
    final type = FileSystemEntity.typeSync(root, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.directory) {
      refuse('is not a directory', move);
      return false;
    }
    if (File(p.join(root, 'pubspec.yaml')).existsSync()) {
      refuse('holds a pubspec.yaml', move);
      return false;
    }
    if (p.basename(root) == 'lib' &&
        File(p.join(p.dirname(root), 'pubspec.yaml')).existsSync()) {
      refuse('is the lib directory of a package', move);
      return false;
    }
    for (final input in protected) {
      final path = p.normalize(p.absolute(input));
      if (p.isWithin(root, path)) {
        refuse('holds ${_paths.of(path)}, an input of the run', move);
        return false;
      }
    }
    final entries = Directory(root).listSync();
    if (entries.isNotEmpty && !File(p.join(root, manifest)).existsSync()) {
      refuse(
        'holds files but no $manifest, so they were not written by it',
        'Empty the directory, or point output to a new one.',
      );
      return false;
    }
    return true;
  }

  /// Writes [content] to [path] through a temporary file, unless the file
  /// has it already; returns whether it was written.
  static bool _writeFile(String path, String content) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync() == content) return false;
    file.parent.createSync(recursive: true);
    final temp = File('$path.typed_openapi.tmp');
    try {
      temp.writeAsStringSync(content, flush: true);
      temp.renameSync(path);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
    return true;
  }
}
