import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'existing_output.dart';
import 'generated_tree.dart';
import 'output_manifest.dart';
import 'output_stray.dart';
import 'output_target.dart';
import 'real_paths.dart';

/// Why the generator may not replace an output directory (TOA830), and what
/// the user can do.
final class _Refusal {
  const _Refusal(this.why, this.fix);

  /// What is wrong with the directory, as the end of a sentence about it.
  final String why;

  /// What the user can do about it.
  final String fix;
}

/// The files and directories found in an output directory.
final class _Listing {
  const _Listing(this.hashes, this.directories) : refusal = null;

  const _Listing.refused(this.refusal)
    : hashes = const {},
      directories = const {};

  /// The files by relative path, with the SHA-256 of their content.
  final Map<String, String> hashes;

  /// The directories by relative path.
  final Set<String> directories;

  /// Why the directory must not be replaced, when it holds something that
  /// forbids that.
  final _Refusal? refusal;
}

/// Looks into an output directory (or the backup that would become it) and
/// decides whether the generator may replace what is in it.
final class OutputInspector {
  /// Creates an inspector that reports to the bag and names paths with the
  /// display paths.
  OutputInspector(this._diagnostics, this._paths);

  static const _move =
      'Point output to a directory of its own, such as lib/src/<client>.';

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// What [dir] holds, or null after reporting why the generator may not
  /// replace it (TOA830). [dir] is the output of [target] or the backup that
  /// becomes it. [generated] is the tree the run writes: a file that already
  /// holds its content is never lost, so it is no stray. With [force] strays
  /// are reported in the result instead of refused; a package, a link or an
  /// input of the run never are.
  ExistingOutput? inspect(
    OutputTarget target,
    String dir,
    GeneratedTree generated, {
    required bool force,
  }) {
    final type = FileSystemEntity.typeSync(dir, followLinks: false);
    if (type == FileSystemEntityType.notFound) return ExistingOutput.none;
    final inputs = target.presentInputs;
    final location = _locationRefusal(target.root, dir, type, inputs);
    if (location != null) return _refuse(target, dir, location);
    final listing = _list(dir, inputs);
    if (listing.refusal case final refusal?) {
      return _refuse(target, dir, refusal);
    }
    final _Listing(:hashes, :directories) = listing;
    if (hashes.isEmpty) return ExistingOutput(hashes, directories);
    final written = OutputManifest.read(
      File(p.join(dir, OutputManifest.fileName)),
    );
    final strays = _strays(hashes, written, generated);
    if (strays.isEmpty) return ExistingOutput(hashes, directories);
    if (force) return ExistingOutput(hashes, directories, strays);
    return _refuse(
      target,
      dir,
      _straysRefusal(
        strays,
        written,
        hasManifestFile: hashes.containsKey(OutputManifest.fileName),
      ),
    );
  }

  /// Reports [refusal] as TOA830 for the directory [dir] of [target] and
  /// returns null.
  ExistingOutput? _refuse(OutputTarget target, String dir, _Refusal refusal) {
    final root = target.root;
    final subject = dir == root
        ? 'its output directory ${_paths.of(root)}'
        : 'the backup ${_paths.of(dir)} of its output directory '
              '${_paths.of(root)}';
    _diagnostics.report(
      .outputNotOwned,
      'Client "${target.client.name}" is not generated: $subject '
      '${refusal.why}.',
      file: _paths.of(root),
      fix: refusal.fix,
    );
    return null;
  }

  /// Why [dir] cannot be an output directory whatever its content: it is
  /// not a directory, is a link, is or holds a package, or holds one of
  /// [inputs].
  _Refusal? _locationRefusal(
    String root,
    String dir,
    FileSystemEntityType type,
    List<String> inputs,
  ) {
    if (type == FileSystemEntityType.link) {
      return const _Refusal(
        'is a symbolic link, which the generator does not follow',
        _move,
      );
    }
    if (type != FileSystemEntityType.directory) {
      return const _Refusal('is not a directory', _move);
    }
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      return const _Refusal('holds a pubspec.yaml', _move);
    }
    if (p.basename(root) == 'lib' &&
        File(p.join(p.dirname(root), 'pubspec.yaml')).existsSync()) {
      return const _Refusal('is the lib directory of a package', _move);
    }
    for (final input in inputs) {
      if (RealPaths.isWithin(dir, input)) {
        return _Refusal(
          'holds ${_paths.of(input)}, an input of the run',
          _move,
        );
      }
    }
    return null;
  }

  /// Everything in [dir] with the hash of every file, or the reason it must
  /// not be replaced: a symbolic link, or a file that is one of [inputs]
  /// (whatever its path, an input is never deleted).
  _Listing _list(String dir, List<String> inputs) {
    final entries = Directory(
      dir,
    ).listSync(recursive: true, followLinks: false);
    final lengths = {
      for (final input in inputs) input: File(input).lengthSync(),
    };
    final hashes = <String, String>{};
    final directories = <String>{};
    for (final entry in entries) {
      final path = p.posix.joinAll(p.split(p.relative(entry.path, from: dir)));
      switch (entry) {
        case Link():
          return _Listing.refused(
            _Refusal(
              'holds a symbolic link, $path, which the generator does not '
                  'follow',
              'Remove the link, or point output to a new directory.',
            ),
          );
        case Directory():
          directories.add(path);
        case _:
          final refusal = _inputRefusal(entry, lengths);
          if (refusal != null) return _Listing.refused(refusal);
          hashes[path] = OutputManifest.hashOf(
            File(entry.path).readAsBytesSync(),
          );
      }
    }
    return _Listing(hashes, directories);
  }

  /// Why [entry] cannot stay in the output: it is one of the inputs, whose
  /// size is in [lengths], by identity.
  _Refusal? _inputRefusal(FileSystemEntity entry, Map<String, int> lengths) {
    for (final MapEntry(key: input, value: length) in lengths.entries) {
      if (File(entry.path).lengthSync() == length &&
          FileSystemEntity.identicalSync(entry.path, input)) {
        return _Refusal(
          'holds ${_paths.of(entry.path)}, which is the input '
          '${_paths.of(input)} of the run',
          _move,
        );
      }
    }
    return null;
  }

  /// The files of [hashes] that the generator may not replace, sorted by
  /// path: those [written] does not list or lists with another hash, and
  /// the manifest itself when it is not one of this generator.
  List<OutputStray> _strays(
    Map<String, String> hashes,
    OutputManifest? written,
    GeneratedTree generated,
  ) {
    final strays = <OutputStray>[];
    for (final MapEntry(key: path, value: hash)
        in hashes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      if (generated.hashes[path] == hash) continue;
      if (path == OutputManifest.fileName) {
        if (written == null) {
          strays.add(
            OutputStray(
              path,
              'not a manifest of ${OutputManifest.generatorName}',
            ),
          );
        }
        continue;
      }
      final stray = OutputManifest.strayReason(written, path, hash);
      if (stray != null) strays.add(OutputStray(path, stray));
    }
    return strays;
  }

  /// The refusal for [strays] when `force` is not set. [written] is the
  /// manifest of this generator, if the directory has one.
  _Refusal _straysRefusal(
    List<OutputStray> strays,
    OutputManifest? written, {
    required bool hasManifestFile,
  }) {
    final others = [
      for (final stray in strays)
        if (stray.path != OutputManifest.fileName || written != null) stray,
    ];
    final names = [
      for (final stray in others.take(8)) '${stray.path} (${stray.reason})',
      if (others.length > 8) 'and ${others.length - 8} more',
    ].join(', ');
    final list = names.isEmpty ? '' : ': $names';
    final hashless = strays.any((s) => s.reason.startsWith('no hash'));
    const manifest = OutputManifest.fileName;
    const generator = OutputManifest.generatorName;
    final why = written != null
        ? 'holds files that the generator did not write or that changed '
              'since it wrote them, and it would delete them$list'
        : hasManifestFile
        ? 'holds a $manifest that is not a manifest of $generator, so '
              'its files were not written by it$list'
        : 'holds files but no $manifest, so they were not written by it'
              '$list';
    return _Refusal(
      why,
      hashless
          ? 'Run generate --force once: the manifest it writes has the '
                'hash of every file.'
          : 'Move them out of the directory, or run generate --force to '
                'replace them.',
    );
  }
}
