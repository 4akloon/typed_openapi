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
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .inputNotFound,
        'Spec file $file does not exist.',
        file: file,
        fix: 'Check "input" in the config, or download a fresh snapshot.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .inputUnreadable,
        'Spec path $file is a directory, not a file.',
        file: file,
        fix: 'Point "input" at the spec file itself.',
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
  /// JSON and YAML go through the same YAML parser, so both get positions.
  /// A JSON file the YAML parser rejects (for example, because of a
  /// duplicate key) is read again with `jsonDecode`, without positions.
  SpecDocument? parse(String text, String file, {Uri? uri}) {
    final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
    final YamlNode node;
    try {
      node = loadYamlNode(text, sourceUrl: Uri.file(file));
    } on YamlException catch (e) {
      return _parseJsonFallback(text, file, location, e);
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
    final root = _toPlain(node, .root, spans, file)! as Map<String, Object?>;
    return SpecDocument(file: file, uri: location, root: root, spans: spans);
  }

  SpecDocument? _parseJsonFallback(
    String text,
    String file,
    Uri uri,
    YamlException error,
  ) {
    final duplicate = error.message.startsWith('Duplicate mapping key');
    if (p.extension(file).toLowerCase() != '.json') {
      _diagnostics.report(
        duplicate ? .duplicateKey : .parseError,
        error.message,
        severity: .error,
        file: file,
        span: error.span,
      );
      return null;
    }
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      if (!duplicate) {
        _diagnostics.report(
          .parseError,
          error.message,
          file: file,
          span: error.span,
        );
        return null;
      }
      _diagnostics.report(
        .duplicateKey,
        error.message,
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
      final offset = e.offset;
      _diagnostics.report(
        .parseError,
        e.message,
        file: file,
        span: offset == null
            ? null
            : SourceFile.fromString(text, url: uri).span(offset, offset),
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

  Object? _toPlain(
    YamlNode node,
    JsonPointer pointer,
    Map<String, SourceSpan> spans,
    String file,
  ) {
    spans[pointer.value] = node.span;
    switch (node) {
      case YamlMap():
        final map = <String, Object?>{};
        final keys = <String, YamlNode>{};
        for (final MapEntry(:key, :value) in node.nodes.entries) {
          final keyNode = key as YamlNode;
          final name = '${keyNode.value}';
          final earlier = keys[name];
          if (earlier != null) {
            _diagnostics.report(
              .duplicateKey,
              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
              'same key "$name" in JSON; the last value is used.',
              file: file,
              pointer: pointer.child(name),
              span: keyNode.span,
              fix: 'Remove one of the keys.',
            );
          }
          keys[name] = keyNode;
          map[name] = _toPlain(value, pointer.child(name), spans, file);
        }
        return map;
      case YamlList():
        return <Object?>[
          for (var i = 0; i < node.nodes.length; i++)
            _toPlain(node.nodes[i], pointer.child(i), spans, file),
        ];
      default:
        return node.value;
    }
  }
}
