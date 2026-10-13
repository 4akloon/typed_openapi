import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_listing.dart';
import 'corpus_exception.dart';

/// Extracts one directory of a `.tar.gz` archive with the system `tar`
/// (GNU tar on Linux, bsdtar on macOS and Windows).
final class ArchiveExtractor {
  /// Creates the extractor.
  const ArchiveExtractor();

  /// Writes the directory [root] of the archive [bytes], which sits below
  /// the archive's one top directory (as in a GitHub tarball), into
  /// [target]; [target] must not exist.
  Future<void> extract(List<int> bytes, String root, String target) async {
    // Next to the target, so the final rename stays on one file system.
    Directory(p.dirname(target)).createSync(recursive: true);
    final temp = Directory(p.dirname(target)).createTempSync('.extract_');
    try {
      final archive = p.join(temp.path, 'archive.tar.gz');
      File(archive).writeAsBytesSync(bytes);
      final listing = await ArchiveListing.of(archive);
      final top = listing.top;
      final kept = '$top/$root';
      listing.check(kept);
      await _tar(['-xzf', archive, '-C', temp.path, kept]);
      Directory(p.joinAll([temp.path, top, ...root.split('/')])).renameSync(
        target,
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  static Future<String> _tar(List<String> arguments) async {
    final result = await Process.run('tar', arguments);
    if (result.exitCode != 0) {
      throw CorpusException('tar ${arguments.first} failed: ${result.stderr}');
    }
    return '${result.stdout}';
  }
}
