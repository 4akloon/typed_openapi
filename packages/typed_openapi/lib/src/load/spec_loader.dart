import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import 'nesting_scanner.dart';
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
    final found = const NestingScanner().scan(text);
    if (found != null) {
      final span = SourceFile.fromString(
        text,
        url: location,
      ).span(found.offset, found.offset + 1);
      switch (found.problem) {
        case .tooDeep:
          _diagnostics.report(
            .nestingTooDeep,
            'The document nests deeper than ${NestingScanner.maxDepth} '
            'levels.',
            file: file,
            span: span,
          );
        case .aliasKey:
          _diagnostics.report(
            .aliasExpansionTooLarge,
            'OpenAPI keys are strings. In a document with aliases, an alias '
            'used as a mapping key, an explicit "?" key or a collection '
            'used as a key can expand without bound, so the document is '
            'not read.',
            file: file,
            span: span,
            fix: 'Write the key out as a plain string.',
          );
      }
      return null;
    }
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
    final converter = _PlainConverter(
      _diagnostics,
      file,
      max(
        _PlainConverter.minBudget,
        _PlainConverter.budgetPerChar * text.length,
      ),
      mayHaveAliases: text.contains('*'),
    );
    final root = converter.convert(node, .root, 0);
    if (converter.failed) return null;
    return SpecDocument(
      file: file,
      uri: location,
      root: root! as Map<String, Object?>,
      spans: converter.spans,
    );
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
}

/// Turns a YAML node tree into plain values and records the span of every
/// node.
///
/// YAML aliases make the tree a graph that shares nodes, so walking it as a
/// tree can take far more steps, and go far deeper, than the text suggests.
/// The text-level `NestingScanner` cannot see that, so the conversion
/// enforces both limits itself: it stops at the first node deeper than
/// [NestingScanner.maxDepth] (`nesting-too-deep`) and once the nodes it has
/// converted have cost more than its budget (`alias-expansion-too-large`).
/// Either is reported once, at that node, and sets [failed].
///
/// Every converted node, whether read for the first time or reached again
/// through an alias, costs the length of its JSON pointer plus one. The
/// pointer string is what a node keeps in [spans], so the sum of the costs
/// is the memory the conversion holds and the time it spends. Ordinary
/// specs cost a few times their text length, far below the budget; aliases
/// of a deep node or of a node under a long key add up quickly.
final class _PlainConverter {
  _PlainConverter(
    this._diagnostics,
    this._file,
    this._budget, {
    required this.mayHaveAliases,
  });

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = 16000000;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = 100;

  final DiagnosticBag _diagnostics;
  final String _file;
  int _budget;

  /// Whether the text may contain aliases, which decides how a depth error
  /// is worded.
  final bool mayHaveAliases;

  /// The source range of every converted node, by pointer value.
  final Map<String, SourceSpan> spans = {};

  /// Whether a limit was hit; the converted value is then incomplete.
  bool failed = false;

  /// Converts [node], which is at [pointer], [depth] collections deep (the
  /// root is 0, as for the `NestingScanner`).
  Object? convert(YamlNode node, JsonPointer pointer, int depth) {
    if (failed) return null;
    _budget -= pointer.value.length + 1;
    if (_budget < 0) {
      _fail(
        .aliasExpansionTooLarge,
        mayHaveAliases
            ? 'YAML aliases expand to far more nodes than the text has; the '
                  'document is not read.'
            : 'The JSON pointers of the document\'s nodes add up to more than '
                  'the supported size, because of very long keys or very '
                  'deep nesting; the document is not read.',
        node,
        pointer,
        fix: mayHaveAliases
            ? 'Remove the nested aliases.'
            : 'Shorten the longest keys.',
      );
      return null;
    }
    final isCollection = node is YamlMap || node is YamlList;
    if (isCollection && depth > NestingScanner.maxDepth) {
      _fail(
        .nestingTooDeep,
        'The document nests deeper than ${NestingScanner.maxDepth} levels'
        '${mayHaveAliases ? ', counting what its aliases expand to' : ''}.',
        node,
        pointer,
      );
      return null;
    }
    spans[pointer.value] = node.span;
    switch (node) {
      case YamlMap():
        final map = <String, Object?>{};
        final keys = <String, YamlNode>{};
        for (final MapEntry(:key, :value) in node.nodes.entries) {
          if (failed) return null;
          final keyNode = key as YamlNode;
          final name = '${keyNode.value}';
          final earlier = keys[name];
          if (earlier != null) {
            _diagnostics.report(
              .duplicateKey,
              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
              'same key "$name" in JSON; the last value is used.',
              file: _file,
              pointer: pointer.child(name),
              span: keyNode.span,
              fix: 'Remove one of the keys.',
            );
          }
          keys[name] = keyNode;
          map[name] = convert(value, pointer.child(name), depth + 1);
        }
        return map;
      case YamlList():
        final list = <Object?>[];
        for (var i = 0; i < node.nodes.length; i++) {
          if (failed) return null;
          list.add(convert(node.nodes[i], pointer.child(i), depth + 1));
        }
        return list;
      default:
        return node.value;
    }
  }

  void _fail(
    DiagnosticCode code,
    String message,
    YamlNode node,
    JsonPointer pointer, {
    String? fix,
  }) {
    failed = true;
    _diagnostics.report(
      code,
      message,
      file: _file,
      pointer: pointer,
      span: node.span,
      fix: fix,
    );
  }
}
