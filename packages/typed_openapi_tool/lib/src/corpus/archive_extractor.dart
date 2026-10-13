import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_listing.dart';
import 'tar_runner.dart';

/// Extracts one directory of a `.tar.gz` archive with the system `tar`
/// (GNU tar on Linux, bsdtar on macOS and Windows).
final class ArchiveExtractor {
  /// Creates the extractor; each `tar` it runs gets [tar]'s time limit.
  const ArchiveExtractor({this.tar = const TarRunner()});

  /// Runs the system `tar`.
  final TarRunner tar;

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
      final listing = await ArchiveListing.of(archive, tar);
      final top = listing.top;
      final kept = '$top/$root';
      listing.check(kept);
      await tar.run(['-xzf', archive, '-C', temp.path, kept]);
      Directory(p.joinAll([temp.path, top, ...root.split('/')])).renameSync(
        target,
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  }
}
