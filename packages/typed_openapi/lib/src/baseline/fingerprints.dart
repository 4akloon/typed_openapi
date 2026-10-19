import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/json_pointer.dart';
import 'anchor_index.dart';

/// The anchors and fingerprints of a client's diagnostics, by which its
/// baseline file matches them.
///
/// A fingerprint is the first 12 hex digits of the SHA-256 of the JSON
/// array `[code, anchor, args]` ([Diagnostic.args]). The message text and
/// the line and column are not part of it, so rewording a message or
/// editing the spec elsewhere keeps it.
///
/// An anchor is `@<address>#<pointer>` when [AnchorIndex] has a logical
/// address for the place (`@/operations/GET ~1pets/parameters/query:limit#/schema`),
/// and `<file>#<pointer>` otherwise, with the file relative to the baseline
/// file's directory in `/` form (`api.yaml#/info`).
final class Fingerprints {
  /// Creates the fingerprints of diagnostics about the spec [_index]
  /// indexes, for the baseline file at [baselineFile]; [_paths] reads the
  /// file names diagnostics carry.
  Fingerprints(
    this._index,
    String baselineFile, [
    this._paths = const DisplayPaths(),
  ]) : _baselineDirectory = p.dirname(_paths.absolute(baselineFile));

  /// How many hex digits of the hash a fingerprint keeps.
  static const length = 12;

  final AnchorIndex _index;
  final DisplayPaths _paths;
  final String _baselineDirectory;

  /// The fingerprint of [diagnostic].
  String of(Diagnostic diagnostic) =>
      hash(diagnostic.code, anchorOf(diagnostic), diagnostic.args);

  /// Where [diagnostic] is, written to survive edits elsewhere in the spec.
  String anchorOf(Diagnostic diagnostic) {
    final file = diagnostic.file;
    final pointer = diagnostic.pointer;
    if (file == null) return pointer?.value ?? '';
    if (pointer != null) {
      if (_index.addressOf(file, pointer) case (final address, final rest)) {
        final at = address.fold(JsonPointer.root, (a, key) => a.child(key));
        return '@${at.value.substring(1)}${rest.value}';
      }
    }
    return '${_fileName(file)}${pointer?.value ?? ''}';
  }

  /// The fingerprint of a [code] finding at [anchor] with [args].
  static String hash(DiagnosticCode code, String anchor, List<String> args) {
    final input = jsonEncode([code.id, anchor, args]);
    return '${sha256.convert(utf8.encode(input))}'.substring(0, length);
  }

  String _fileName(String file) {
    final full = _paths.absolute(file);
    try {
      return p.posix.joinAll(
        p.split(p.relative(full, from: _baselineDirectory)),
      );
    } on p.PathException {
      // On another drive than the baseline file.
      return DisplayPaths.withSlashes(full);
    }
  }
}
