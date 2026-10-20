import 'package:path/path.dart' as p;

/// How reports name files: relative to the working directory when the file
/// is inside it, absolute otherwise.
///
/// Every report format uses the same names, so a path printed by `check`
/// opens from the directory the command ran in. The separator is `/` on every
/// platform, so a report, a baseline and a CI annotation are the same on
/// Windows as elsewhere; an absolute Windows path keeps its drive letter
/// (`C:/work/specs/api.yaml`).
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
      return withSlashes(p.relative(full, from: base));
    }
    return withSlashes(full);
  }

  /// [path] with `/` as the separator.
  ///
  /// Only a Windows [style] has a separator to replace: on other systems a
  /// backslash is part of a file name.
  static String withSlashes(String path, [p.Style? style]) =>
      (style ?? p.style) == p.Style.windows
      ? path.replaceAll(p.windows.separator, '/')
      : path;
}
