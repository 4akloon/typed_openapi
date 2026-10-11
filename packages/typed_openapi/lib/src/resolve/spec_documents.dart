import 'dart:io';

import 'package:path/path.dart' as p;

import '../load/spec_document.dart';
import '../load/spec_loader.dart';

/// The documents of one spec: the root document and every file its `$ref`s
/// reach, each loaded once and keyed by absolute URI.
final class SpecDocuments {
  /// Creates the set for [root]; other files are read with [_loader].
  SpecDocuments(this._loader, this.root) {
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
    final path = p.fromUri(uri);
    final document =
        FileSystemEntity.typeSync(path) == FileSystemEntityType.file
        ? _loader.load(path, displayPath: displayPath(uri))
        : null;
    return _documents[uri] = document;
  }

  /// How diagnostics name the file at [uri].
  String displayPath(Uri uri) {
    if (uri == root.uri) return root.file;
    final relative = p.relative(
      p.fromUri(uri),
      from: p.dirname(p.fromUri(root.uri)),
    );
    return p.normalize(p.join(p.dirname(root.file), relative));
  }
}
