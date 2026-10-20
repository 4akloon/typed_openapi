import 'dart:io';
import 'method_scanner.dart';

/// Measures the size limits of `CLAUDE.md` ("Code quality rules") on one
/// package and turns a measurement into failure messages.
///
/// The measurement needs no analyzer: the generator core must not depend on
/// it, and neither does this test. Files are counted with the newline count
/// that `wc -l` gives. Methods are found by indentation, see [measureMethods].
///
/// Both limits are a ratchet: a unit over its limit that is in the allowlist
/// may only shrink, and a unit over its limit that is not in it fails.
final class SizeLimits {
  /// Measures the package whose root is [packageRoot] (the directory with
  /// `pubspec.yaml`, where `dart test` runs).
  SizeLimits(this.packageRoot);

  /// The most lines a file in `lib/` may have.
  static const int libFileLimit = 300;

  /// The most lines a file in `test/` may have.
  static const int testFileLimit = 500;

  /// The most lines a method may have, signature and braces included.
  static const int methodLimit = 40;

  /// A directory whose files are not ours: the vendored YAML parser.
  static const String _vendored = 'lib/src/load/yaml/';

  /// The package root, the base of every key this class returns.
  final String packageRoot;

  /// The number of lines (as `wc -l` counts) of every file in `lib/` and
  /// `test/` over its limit, keyed by the path relative to [packageRoot].
  Map<String, int> measureFiles() {
    final result = <String, int>{};
    for (final entry in _dartFiles().entries) {
      final lines = _newlines(entry.value.readAsStringSync());
      if (lines > _fileLimit(entry.key)) {
        result[entry.key] = lines;
      }
    }
    return result;
  }

  /// The number of lines of every method in `lib/` over [methodLimit],
  /// keyed by `path#Class.name`.
  ///
  /// A method is found by indentation, which `dart format` makes reliable:
  ///
  /// - it starts on a line indented by exactly two spaces, inside a type,
  ///   that ends with `{`, or on the line before an indented `) {`, `}) {` or
  ///   `: initializer {` that ends with `{`;
  /// - it ends on the next line that is exactly two spaces and `}`;
  /// - its length counts from the signature to that line, annotations and
  ///   doc comments excluded.
  ///
  /// A member with an expression body (`=>`) is measured from its signature
  /// to the `;` that ends it.
  ///
  /// Control statements, closures, assignments and type headers are not
  /// methods (the line is skipped). A one-line `{}` body and a nested type
  /// are not seen: false negatives are accepted, a false positive is a bug
  /// of this class.
  /// Constructors, getters, setters and operators count as methods. A name
  /// that repeats in one type gets `@2`, `@3`... in file order. Test files are
  /// not measured: their `main` holds the test closures.
  Map<String, int> measureMethods() {
    final result = <String, int>{};
    for (final entry in _dartFiles().entries) {
      if (!entry.key.startsWith('lib/')) {
        continue;
      }
      final lines = entry.value.readAsStringSync().split('\n');
      for (final method in const MethodScanner().methodsOf(lines)) {
        if (method.length > methodLimit) {
          result['${entry.key}#${method.name}'] = method.length;
        }
      }
    }
    return result;
  }

  /// The failures of the file limit; empty when every file is within its
  /// limit, in [allowlist] and not grown, or in [permanent].
  ///
  /// [allowlist] maps a path to the lines it had when it was listed. A listed
  /// file that shrank or is within its limit is a stale entry, which does not
  /// fail. [permanent] holds files that are exempt for good.
  List<String> fileFailures({
    required Map<String, int> allowlist,
    required Set<String> permanent,
  }) {
    final failures = <String>[];
    for (final entry in measureFiles().entries) {
      final path = entry.key;
      final lines = entry.value;
      final limit = _fileLimit(path);
      final recorded = allowlist[path];
      if (permanent.contains(path)) {
        continue;
      }
      if (recorded == null) {
        failures.add(
          '$path has $lines lines, over the limit of $limit. Split it by '
          'responsibility (CLAUDE.md, Code quality rules); do not add it to '
          'the allowlist.',
        );
      } else if (lines > recorded) {
        failures.add(
          '$path has $lines lines, it had $recorded: an allowlisted file may '
          'only shrink. Move the new code into a new file or class and keep '
          'this one at $recorded or fewer (the limit is $limit).',
        );
      }
    }
    return failures;
  }

  /// The failures of the method limit; empty when every method is within
  /// [methodLimit], or in [allowlist] and not grown.
  ///
  /// [allowlist] maps `path#Class.name` to the lines the method had when it
  /// was listed. A listed method that shrank or is within the limit is a
  /// stale entry, which does not fail.
  List<String> methodFailures({required Map<String, int> allowlist}) {
    final failures = <String>[];
    for (final entry in measureMethods().entries) {
      final recorded = allowlist[entry.key];
      if (recorded == null) {
        failures.add(
          '${entry.key} has ${entry.value} lines, over the limit of '
          '$methodLimit. Split it into named steps (CLAUDE.md, Code quality '
          'rules); do not add it to the allowlist.',
        );
      } else if (entry.value > recorded) {
        failures.add(
          '${entry.key} has ${entry.value} lines, it had $recorded: an '
          'allowlisted method may only shrink. Extract the new code into a '
          'method of its own (the limit is $methodLimit).',
        );
      }
    }
    return failures;
  }

  /// Every `.dart` file of `lib/` and `test/` outside the vendored parser,
  /// by path relative to [packageRoot], in path order.
  Map<String, File> _dartFiles() {
    final files = <String, File>{};
    for (final folder in const ['lib', 'test']) {
      final directory = Directory('$packageRoot/$folder');
      if (!directory.existsSync()) {
        continue;
      }
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final relative = entity.path
            .substring(packageRoot.length + 1)
            .replaceAll(r'\', '/');
        if (!relative.startsWith(_vendored)) {
          files[relative] = entity;
        }
      }
    }
    return Map.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// The limit of the file at [path].
  int _fileLimit(String path) =>
      path.startsWith('test/') ? testFileLimit : libFileLimit;

  /// The number of line breaks in [text], what `wc -l` prints.
  int _newlines(String text) =>
      text.codeUnits.where((unit) => unit == 0x0A).length;
}
