import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import 'spec_document.dart';
import 'yaml_composer.dart';

/// Reads spec files (JSON or YAML) into [SpecDocument]s.
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class SpecLoader {
  /// Creates a loader that reports to [_diagnostics].
  const SpecLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the spec file at [path].
  ///
  /// [displayPath] is used in diagnostics instead of [path]. Returns null
  /// when the file cannot be used at all.
  SpecDocument? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .inputNotFound,
        'Spec file $file does not exist.',
        file: file,
        fix: 'Check "input" in the config, or download a fresh snapshot.',
        backendFix: 'Check the path of the spec file.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .inputUnreadable,
        'Spec path $file is a directory, not a file.',
        file: file,
        fix: 'Point "input" at the spec file itself.',
        backendFix: 'Give the path of the spec file, not of a directory.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .inputUnreadable,
        'Cannot read $file: ${e.message}.',
        file: file,
        fix: 'Save the spec as UTF-8 and check the file permissions.',
      );
      return null;
    }
    return parse(text, file, uri: p.toUri(p.normalize(p.absolute(path))));
  }

  /// Parses spec [text]; [file] names it in diagnostics.
  ///
  /// [uri] is the absolute location of the text, the base for relative
  /// `$ref`s; it defaults to [file] resolved against the current directory.
  /// JSON and YAML go through the same [YamlComposer], so both get
  /// positions. A `.json` file the YAML parser rejects is read again with
  /// `jsonDecode`, without positions.
  SpecDocument? parse(String text, String file, {Uri? uri}) {
    final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
    final json = p.extension(file).toLowerCase() == '.json';
    final composed = YamlComposer(
      _diagnostics,
    ).compose(text, file: file, uri: location, json: json);
    if (composed == null) return null;
    if (composed.syntaxError case final error?) {
      if (json) return _parseJsonFallback(text, file, location, error);
      _diagnostics.report(
        .parseError,
        error.message,
        file: file,
        span: error.span,
      );
      return null;
    }
    final root = composed.root;
    if (root is! Map<String, Object?>) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
        span: composed.spans[JsonPointer.root.value],
      );
      return null;
    }
    return SpecDocument(
      file: file,
      uri: location,
      root: root,
      spans: composed.spans,
    );
  }

  SpecDocument? _parseJsonFallback(
    String text,
    String file,
    Uri uri,
    ({String message, SourceSpan span}) error,
  ) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      _diagnostics.report(
        .parseError,
        error.message,
        file: file,
        span: error.span,
      );
      return null;
    }
    if (root is! Map<String, Object?>) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
      );
      return null;
    }
    _diagnostics.report(
      .positionsUnavailable,
      'Read $file without source positions; '
      'diagnostics for it show JSON pointers only.',
      file: file,
    );
    return SpecDocument(file: file, uri: uri, root: root, spans: const {});
  }
}
