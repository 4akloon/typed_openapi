import 'package:path/path.dart' as p;

/// How reports name files: relative to the working directory when the file
/// is inside it, absolute otherwise.
///
/// Every report format uses the same names, so a path printed by `check`
/// opens from the directory the command ran in.
final class DisplayPaths {
  /// Names files relative to [_workingDirectory], by default the current
  /// directory of the process.
  const DisplayPaths([this._workingDirectory]);

  final String? _workingDirectory;

  /// The absolute, normalized working directory.
  String get workingDirectory =>
      p.normalize(p.absolute(_workingDirectory ?? p.current));

  /// [path] as an absolute, normalized path; a relative [path] is relative
  /// to [workingDirectory].
  String absolute(String path) => p.normalize(p.join(workingDirectory, path));

  /// How reports name the file at [path]: relative to [workingDirectory]
  /// when it is inside it, absolute otherwise.
  String of(String path) {
    final full = absolute(path);
    final base = workingDirectory;
    if (p.equals(full, base) || p.isWithin(base, full)) {
      return p.relative(full, from: base);
    }
    return full;
  }
}
