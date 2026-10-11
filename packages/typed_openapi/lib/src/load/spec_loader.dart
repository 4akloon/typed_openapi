import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import 'spec_document.dart';

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
    final source = File(path);
    if (!source.existsSync()) {
      _diagnostics.report(
        .inputNotFound,
        'Spec file $file does not exist.',
        file: file,
        fix: 'Check "input" in the config, or download a fresh snapshot.',
      );
      return null;
    }
    final String text;
    try {
      text = source.readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .inputUnreadable,
        'Cannot read $file: ${e.message}.',
        file: file,
        fix: 'Save the spec as UTF-8 and check the file permissions.',
      );
      return null;
    }
    return parse(text, file);
  }

  /// Parses spec [text]; [file] names it in diagnostics.
  ///
  /// JSON and YAML go through the same YAML parser, so both get positions.
  /// A JSON file the YAML parser rejects (for example, because of a
  /// duplicate key) is read again with `jsonDecode`, without positions.
  SpecDocument? parse(String text, String file) {
    final YamlNode node;
    try {
      node = loadYamlNode(text, sourceUrl: Uri.file(file));
    } on YamlException catch (e) {
      return _parseJsonFallback(text, file, e);
    }
    if (node is! YamlMap) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
        span: node.span,
      );
      return null;
    }
    final spans = <String, SourceSpan>{};
    final root = _toPlain(node, .root, spans)! as Map<String, Object?>;
    return SpecDocument(file: file, root: root, spans: spans);
  }

  SpecDocument? _parseJsonFallback(
    String text,
    String file,
    YamlException error,
  ) {
    final duplicate = error.message.startsWith('Duplicate mapping key');
    final decoded = p.extension(file).toLowerCase() == '.json'
        ? _tryDecodeJson(text)
        : null;
    if (decoded == null) {
      _diagnostics.report(
        duplicate ? .duplicateKey : .parseError,
        error.message,
        severity: .error,
        file: file,
        span: error.span,
      );
      return null;
    }
    if (duplicate) {
      _diagnostics.report(
        .duplicateKey,
        '${error.message} The last value is used.',
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
    }
    _diagnostics.report(
      .positionsUnavailable,
      'Read $file without source positions; '
      'diagnostics for it show JSON pointers only.',
      file: file,
    );
    final (root,) = decoded;
    if (root is! Map<String, Object?>) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
      );
      return null;
    }
    return SpecDocument(file: file, root: root, spans: const {});
  }

  static (Object?,)? _tryDecodeJson(String text) {
    try {
      return (jsonDecode(text),);
    } on FormatException {
      return null;
    }
  }

  static Object? _toPlain(
    YamlNode node,
    JsonPointer pointer,
    Map<String, SourceSpan> spans,
  ) {
    spans[pointer.value] = node.span;
    return switch (node) {
      YamlMap() => <String, Object?>{
        for (final MapEntry(:key, :value) in node.nodes.entries)
          '${(key as YamlNode).value}': _toPlain(
            value,
            pointer.child('${key.value}'),
            spans,
          ),
      },
      YamlList() => <Object?>[
        for (var i = 0; i < node.nodes.length; i++)
          _toPlain(node.nodes[i], pointer.child(i), spans),
      ],
      _ => node.value,
    };
  }
}
