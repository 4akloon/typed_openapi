import 'dart:io';

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

  /// A line that opens a type: `class A {`, `enum E {`, `extension on X {`.
  static final RegExp _typeHeader = RegExp(
    r'^(?:[a-z]+ )*(?:class|mixin|enum|extension(?: type)?)\s+(?:on\s+)?'
    r'([A-Za-z_$][\w$]*)',
  );

  /// The declaration keywords that never start a method.
  static final RegExp _notAMethod = RegExp(
    r'(?:^|\s)(?:class|enum|mixin|extension|typedef)\s',
  );

  /// A statement or expression, which is not a declaration.
  static final RegExp _statement = RegExp(
    r'^\s*(?:if|else|for|while|switch|try|catch|do|return|await|throw|final|'
    r'var)\b',
  );

  /// `get name` and `set name`, which have no parameter list to anchor on.
  static final RegExp _accessor = RegExp(r'\b(get|set)\s+([A-Za-z_$][\w$]*)');

  /// The parameter list of a function type: `Function(int a, List<int>)`.
  static final RegExp _functionType = RegExp(
    r'\bFunction\s*\((?:[^()]|\([^()]*\))*\)',
  );

  /// The `(` of a parameter list: the first one that follows a name or the
  /// type parameters of a method.
  static final RegExp _parameterList = RegExp(r'[\w$>]\s*\(');

  /// `operator ==`, `operator []`...
  static final RegExp _operator = RegExp(r'\boperator\s*([^\s(]+)\s*\(');

  /// The name at the end of the text before a parameter list, `Foo.named` or
  /// `run`.
  static final RegExp _callable = RegExp(
    r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)$',
  );

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
      for (final method in _methodsOf(lines)) {
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

  /// The methods found in [lines], in file order.
  List<_Method> _methodsOf(List<String> lines) {
    final methods = <_Method>[];
    final seen = <String, int>{};
    String? type;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && line.codeUnitAt(0) != 0x20) {
        // A type opens or closes in the first column. Other first-column
        // lines (comments, annotations, text of a multi-line string) change
        // nothing.
        if (_typeHeader.firstMatch(line) case final header?) {
          type = header.group(1);
        } else if (line.startsWith('}')) {
          type = null;
        }
        continue;
      }
      if (type == null) {
        continue;
      }
      if (_arrowMember(lines, i) case final arrow?) {
        _record(methods, seen, '$type.${_memberName(type, arrow.name)}', arrow);
        i = arrow.end;
        continue;
      }
      if (!_endsBody(line)) {
        continue;
      }
      final start = _signatureStart(lines, i);
      final end = _closingLine(lines, i);
      final name = start == null ? null : _nameOf(lines[start]);
      if (start == null || end == null || name == null) {
        continue;
      }
      final key = '$type.${_memberName(type, name)}';
      _record(methods, seen, key, (name: name, start: start, end: end));
      i = end;
    }
    return methods;
  }

  /// Adds the member at [span] to [methods] under [key], numbering a repeated
  /// key through [seen].
  void _record(
    List<_Method> methods,
    Map<String, int> seen,
    String key,
    _Span span,
  ) {
    final count = seen.update(key, (n) => n + 1, ifAbsent: () => 1);
    methods.add(
      _Method(count == 1 ? key : '$key@$count', span.end - span.start + 1),
    );
  }

  /// The member with an expression body (`=>`) that starts on line [first],
  /// or null when that line starts none.
  ///
  /// The signature runs over the continuation lines until a `=>` outside
  /// every bracket; a line that ends in `;` or opens a block body first, or
  /// a `=` before the parameter list (a field), is not an arrow member. The
  /// member ends on the first line that ends with `;` and is followed by a
  /// line that is not indented deeper than the member.
  _Span? _arrowMember(List<String> lines, int first) {
    if (!_startsDeclaration(lines[first]) ||
        _statement.hasMatch(lines[first]) ||
        _notAMethod.hasMatch(_beforeParameters(lines[first]))) {
      return null;
    }
    final name = _nameOf(lines[first]);
    final arrow = _arrowLine(lines, first);
    if (name == null || arrow == null) {
      return null;
    }
    for (var i = arrow; i < lines.length; i++) {
      final isLast = i + 1 == lines.length || !lines[i + 1].startsWith('   ');
      if (lines[i].endsWith(';') && isLast) {
        return (name: name, start: first, end: i);
      }
    }
    return null;
  }

  /// The index of the line with the `=>` of the member that starts on line
  /// [first], or null when the member has a block body or is a field.
  int? _arrowLine(List<String> lines, int first) {
    var depth = 0;
    for (var i = first; i < lines.length; i++) {
      if (i > first && !_continues(lines[i])) {
        return null;
      }
      final line = lines[i];
      final text = i == first ? _withoutOperatorName(line) : line;
      for (var c = 0; c < text.length; c++) {
        if (depth == 0 && text.startsWith('=>', c)) {
          return i;
        }
        if (depth == 0 && text[c] == '=' && !text.startsWith('==', c)) {
          return null;
        }
        depth += switch (text[c]) {
          '(' || '[' || '{' => 1,
          ')' || ']' || '}' => -1,
          _ => 0,
        };
      }
      if (depth == 0 && (line.endsWith(';') || line.endsWith('{'))) {
        return null;
      }
    }
    return null;
  }

  /// Whether [line] continues the member above it: it is indented deeper
  /// than a member, or closes a bracket the member opened.
  bool _continues(String line) =>
      line.startsWith('   ') || line.startsWith(RegExp(r'  [)}\]]'));

  /// [line] with the name of an operator (`operator ==`) blanked, so that its
  /// `=` is not read as an assignment.
  String _withoutOperatorName(String line) =>
      line.replaceFirstMapped(_operator, (_) => 'operator x(');

  /// [name] as a member of [type]: a constructor is `new` or its own name
  /// without the type's.
  String _memberName(String type, String name) {
    if (name == type) {
      return 'new';
    }
    return name.startsWith('$type.') ? name.substring(type.length + 1) : name;
  }

  /// Whether [line] could open a method body: it ends with `{` and is
  /// indented by two spaces (a signature) or four (`: initializer {`).
  ///
  /// A line that opens a parameter list (`const Foo({`) also ends with `{`;
  /// it has more `(` than `)` and is not a body, unlike `) {` and `}) {`,
  /// which start with the closing bracket.
  bool _endsBody(String line) {
    if (!line.endsWith('{')) {
      return false;
    }
    final text = line.trimLeft();
    final indent = line.length - text.length;
    if (indent == 4) {
      return text.startsWith(':');
    }
    return indent == 2 &&
        (text.startsWith(RegExp(r'[)}\]]')) ||
            _count(text, '(') == _count(text, ')'));
  }

  /// How often [char] occurs in [text].
  int _count(String text, String char) => char.allMatches(text).length;

  /// The index of the line a method whose body opens on line [open] starts
  /// on, or null when the line is not a method declaration.
  int? _signatureStart(List<String> lines, int open) {
    var start = open;
    while (start > 0 && !_startsDeclaration(lines[start])) {
      start--;
    }
    final text = lines[start];
    final beforeParen = _beforeParameters(text);
    if (!_startsDeclaration(text) ||
        beforeParen.contains('=') ||
        text.contains('=>') ||
        _notAMethod.hasMatch(beforeParen) ||
        _statement.hasMatch(text)) {
      return null;
    }
    return start;
  }

  /// Whether [line] is indented by exactly two spaces and starts a member
  /// (not a continuation: `)`, `}`; not an annotation or a comment).
  bool _startsDeclaration(String line) {
    if (!line.startsWith('  ') || line.startsWith('   ')) {
      return false;
    }
    final text = line.trimLeft();
    return !text.startsWith(')') &&
        !text.startsWith('}') &&
        !text.startsWith('@') &&
        !text.startsWith('//') &&
        !text.startsWith('/*') &&
        !text.startsWith('*');
  }

  /// The name of the member declared on [signature].
  String? _nameOf(String signature) {
    final beforeParen = _beforeParameters(signature);
    if (_accessor.firstMatch(beforeParen) case final accessor?) {
      return accessor.group(1) == 'set'
          ? '${accessor.group(2)}='
          : accessor.group(2);
    }
    if (_operator.firstMatch(signature) case final operator?) {
      return 'operator ${operator.group(1)}';
    }
    return _callable
        .firstMatch(_withoutTypeParameters(beforeParen.trimRight()))
        ?.group(1);
  }

  /// The part of [signature] before its parameter list.
  ///
  /// The list opens at the first `(` that follows a name. A `(` that opens
  /// the parameters of a returned function type (`T Function(int) name(`) or
  /// a record type (`(int, int) name(`) comes first and is skipped.
  String _beforeParameters(String signature) {
    final text = signature.replaceAll(_functionType, 'Function');
    final open = _parameterList.firstMatch(text);
    return open == null ? text : text.substring(0, open.end - 1);
  }

  /// [text] without a trailing `<...>` (the type parameters of a method).
  String _withoutTypeParameters(String text) {
    if (!text.endsWith('>')) {
      return text;
    }
    var depth = 0;
    for (var i = text.length - 1; i >= 0; i--) {
      depth += switch (text[i]) {
        '>' => 1,
        '<' => -1,
        _ => 0,
      };
      if (depth == 0) {
        return text.substring(0, i).trimRight();
      }
    }
    return text;
  }

  /// The index of the first line after [open] that is exactly two spaces and
  /// `}`, or null when the file ends first.
  int? _closingLine(List<String> lines, int open) {
    for (var i = open + 1; i < lines.length; i++) {
      if (lines[i] == '  }') {
        return i;
      }
    }
    return null;
  }
}

/// Where a member sits in a file: its [name] and the first and last line.
typedef _Span = ({String name, int start, int end});

/// One method found by [SizeLimits.measureMethods].
final class _Method {
  /// A method called [name] of [length] lines.
  const _Method(this.name, this.length);

  /// `Class.name`, with `@2`... for a repeated name.
  final String name;

  /// Lines from the signature to the closing brace.
  final int length;
}
