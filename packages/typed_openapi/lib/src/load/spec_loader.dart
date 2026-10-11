import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import 'spec_document.dart';

/// Reads the spec file at [path] (JSON or YAML).
///
/// [displayPath] is used in diagnostics instead of [path]. Problems go to
/// [diagnostics]; returns null when the file cannot be used at all.
SpecDocument? loadSpec(
  String path,
  DiagnosticBag diagnostics, {
  String? displayPath,
}) {
  final file = displayPath ?? path;
  final source = File(path);
  if (!source.existsSync()) {
    diagnostics.report(
      DiagnosticCode.inputNotFound,
      'Spec file $file does not exist.',
      file: file,
      fix: 'Check "input" in the config, or download a fresh snapshot.',
    );
    return null;
  }
  return parseSpec(source.readAsStringSync(), file, diagnostics);
}

/// Parses spec [text]; [file] names it in diagnostics.
///
/// JSON and YAML go through the same YAML parser, so both get positions.
/// A JSON file the YAML parser rejects (for example, because of a duplicate
/// key) is read again with `jsonDecode`, without positions.
SpecDocument? parseSpec(String text, String file, DiagnosticBag diagnostics) {
  final YamlNode node;
  try {
    node = loadYamlNode(text, sourceUrl: Uri.file(file));
  } on YamlException catch (e) {
    return _parseJsonFallback(text, file, e, diagnostics);
  }
  if (node is! YamlMap) {
    diagnostics.report(
      DiagnosticCode.rootNotObject,
      'The document root must be an object.',
      file: file,
      pointer: JsonPointer.root,
      span: node.span,
    );
    return null;
  }
  final spans = <String, SourceSpan>{};
  final root = _toPlain(node, JsonPointer.root, spans)! as Map<String, Object?>;
  return SpecDocument(file: file, root: root, spans: spans);
}

SpecDocument? _parseJsonFallback(
  String text,
  String file,
  YamlException error,
  DiagnosticBag diagnostics,
) {
  final duplicate = error.message.startsWith('Duplicate mapping key');
  final decoded = p.extension(file).toLowerCase() == '.json'
      ? _tryDecodeJson(text)
      : null;
  if (decoded == null) {
    diagnostics.report(
      duplicate ? DiagnosticCode.duplicateKey : DiagnosticCode.parseError,
      error.message,
      severity: Severity.error,
      file: file,
      span: error.span,
    );
    return null;
  }
  if (duplicate) {
    diagnostics.report(
      DiagnosticCode.duplicateKey,
      '${error.message} The last value is used.',
      file: file,
      span: error.span,
      fix: 'Remove the duplicate key from the spec.',
    );
  }
  diagnostics.report(
    DiagnosticCode.positionsUnavailable,
    'Read $file without source positions; '
    'diagnostics for it show JSON pointers only.',
    file: file,
  );
  final (root,) = decoded;
  if (root is! Map<String, Object?>) {
    diagnostics.report(
      DiagnosticCode.rootNotObject,
      'The document root must be an object.',
      file: file,
      pointer: JsonPointer.root,
    );
    return null;
  }
  return SpecDocument(file: file, root: root, spans: const {});
}

(Object?,)? _tryDecodeJson(String text) {
  try {
    return (jsonDecode(text),);
  } on FormatException {
    return null;
  }
}

Object? _toPlain(
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
