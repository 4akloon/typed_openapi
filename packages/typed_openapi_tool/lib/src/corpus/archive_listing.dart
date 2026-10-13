import 'corpus_exception.dart';
import 'tar_runner.dart';

/// The entries of a `.tar.gz` archive, read with the system `tar` before
/// anything is extracted, and the checks that keep an extraction inside its
/// target.
final class ArchiveListing {
  /// Creates the listing of [names]; `_types` holds the first character of
  /// each entry's verbose line (`-` file, `d` directory, `l` symbolic link,
  /// `h` hard link).
  const ArchiveListing._(this.names, this._types);

  /// Lists the archive file [archive] with [tar].
  static Future<ArchiveListing> of(String archive, TarRunner tar) async {
    final names = _lines(await tar.run(['-tzf', archive]));
    final verbose = _lines(await tar.run(['-tvzf', archive]));
    if (names.length != verbose.length) {
      throw const CorpusException(
        'The archive has entry names that tar cannot list reliably.',
      );
    }
    return ArchiveListing._(names, [for (final line in verbose) line[0]]);
  }

  /// The names of the entries, in archive order.
  final List<String> names;

  final List<String> _types;

  /// The one top directory of the archive, as in a GitHub tarball.
  String get top {
    if (names.isEmpty) throw const CorpusException('The archive is empty.');
    return names.first.split('/').first;
  }

  /// Throws a [CorpusException] for an entry that would be written outside
  /// the target (an absolute name or a `..` segment, anywhere in the
  /// archive), and for a link that is [kept] or lies on the way to it or in
  /// it, which could lead a later write or a later read out of the target.
  void check(String kept) {
    for (final (index, name) in names.indexed) {
      final path = name.endsWith('/')
          ? name.substring(0, name.length - 1)
          : name;
      if (_isUnsafe(path)) {
        throw CorpusException('The archive has the unsafe entry "$name".');
      }
      final type = _types[index];
      final isNear = _isWithin(path, kept) || _isWithin(kept, path);
      if (isNear && (type == 'l' || type == 'h')) {
        throw CorpusException(
          'The archive has the link "$name" in or on the way to "$kept"; '
          'links are not extracted.',
        );
      }
      if (_isWithin(kept, path) && type != '-' && type != 'd') {
        throw CorpusException(
          'The archive has "$name", which is neither a file nor a '
          'directory, in "$kept".',
        );
      }
    }
  }

  static final _drive = RegExp('^[A-Za-z]:');

  /// Whether [path] could be written elsewhere than its own place: absolute,
  /// with a backslash or drive, or with an empty, `.` or `..` segment (so a
  /// link written as `./a`, `a//b` or `a/./b` cannot dodge a comparison).
  static bool _isUnsafe(String path) =>
      path.startsWith('/') ||
      path.contains(r'\') ||
      _drive.hasMatch(path) ||
      path.split('/').any((s) => s.isEmpty || s == '.' || s == '..');

  /// Whether [path] is [directory] or lies below it.
  static bool _isWithin(String directory, String path) =>
      path == directory || path.startsWith('$directory/');

  static List<String> _lines(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trimRight(),
  ];
}
