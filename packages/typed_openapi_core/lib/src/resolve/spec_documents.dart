import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/display_paths.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';

/// The documents of one spec: the root document and every file its `$ref`s
/// reach, each loaded once and keyed by absolute URI.
final class SpecDocuments {
  /// Creates the set for [root]; other files are read with [_loader],
  /// except [others], which are already loaded.
  SpecDocuments(
    this._loader,
    this.root, {
    Iterable<SpecDocument> others = const [],
  }) {
    for (final document in others) {
      _documents[document.uri] = document;
    }
    _documents[root.uri] = root;
  }

  final SpecLoader _loader;
  final Map<Uri, SpecDocument?> _documents = {};

  /// The document the spec starts from.
  final SpecDocument root;

  /// The document at [uri], loaded on first use; null when the file does not
  /// exist or cannot be read.
  ///
  /// A file that does not exist is not reported here; one that exists but
  /// cannot be parsed is reported by the loader. Diagnostics name the file
  /// relative to the root document's displayed path.
  SpecDocument? operator [](Uri uri) {
    if (_documents.containsKey(uri)) return _documents[uri];
    final path = _pathOf(uri);
    final document = path != null && exists(uri)
        ? _loader.load(path, displayPath: displayPath(uri))
        : null;
    return _documents[uri] = document;
  }

  /// Every document loaded so far, the root first.
  Iterable<SpecDocument> get loaded => [
    root,
    for (final document in _documents.values)
      if (document != null && document.uri != root.uri) document,
  ];

  /// Whether a file (not a directory) is at [uri].
  ///
  /// False when [uri] does not name a file path, such as one with a
  /// percent-escape that is not UTF-8.
  bool exists(Uri uri) {
    final path = _pathOf(uri);
    return path != null &&
        FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
  }

  /// How diagnostics name the file at [uri]: like the root document, whose
  /// name is relative to the working directory or absolute.
  ///
  /// A file outside the directory the root's relative name starts from is
  /// named by its absolute path, as is every file when the root's name is
  /// absolute.
  String displayPath(Uri uri) {
    if (uri == root.uri) return DisplayPaths.withSlashes(root.file);
    final path = _pathOf(uri);
    final rootPath = _pathOf(root.uri);
    if (path == null || rootPath == null) return '$uri';
    if (p.isAbsolute(root.file)) {
      return DisplayPaths.withSlashes(p.normalize(path));
    }
    final relative = p.relative(path, from: p.dirname(rootPath));
    final name = p.normalize(p.join(p.dirname(root.file), relative));
    return DisplayPaths.withSlashes(
      p.split(name).first == '..' ? p.normalize(path) : name,
    );
  }

  static String? _pathOf(Uri uri) {
    try {
      return p.fromUri(uri);
    } on FormatException {
      return null;
    }
  }
}
