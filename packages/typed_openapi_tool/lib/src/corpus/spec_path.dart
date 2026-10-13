import 'corpus_exception.dart';

/// Checks a path that `corpus.yaml` names inside a spec's cache directory or
/// archive, so no entry can reach a file outside it.
final class SpecPath {
  /// Creates the check.
  const SpecPath();

  static final _drive = RegExp('^[A-Za-z]:');

  /// Returns [value] when it is a relative path of `/`-separated segments,
  /// none empty, `.` or `..`; else throws a [CorpusException] that names the
  /// [entry] and its [key].
  String check(String entry, String key, String value) {
    final isAbsolute =
        value.startsWith('/') || value.contains(r'\') || _drive.hasMatch(value);
    final segments = value.split('/');
    final isPlain = segments.every(
      (s) => s.isNotEmpty && s != '.' && s != '..',
    );
    if (isAbsolute || !isPlain) {
      throw CorpusException(
        'corpus.yaml: $entry has "$key" "$value", which is not a relative '
        'path without empty, "." or ".." segments.',
      );
    }
    return value;
  }
}
