import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import 'override_document_reader.dart';
import 'override_set.dart';

/// Reads a client's overrides file (`typed_openapi.overrides.yaml`, JSON or
/// YAML) into an [OverrideSet].
///
/// Every problem goes to the [DiagnosticBag] given to the constructor, at
/// its position in the overrides file: a missing file is
/// `overrides-not-found`, text that cannot be read and values of the wrong
/// type are `invalid-override`, unknown keys `unknown-override-key`. A bad
/// value is ignored and the rest of the file is read.
final class OverrideLoader {
  /// Creates a loader that reports to [_diagnostics].
  const OverrideLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the overrides file at [path]; [displayPath] names it in
  /// diagnostics. Returns null when the file cannot be used at all.
  OverrideSet? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .overridesNotFound,
        'Overrides file $file does not exist.',
        file: file,
        fix: 'Create it, or fix "overrides" of this client in the config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .invalidOverride,
        'Overrides path $file is a directory, not a file.',
        file: file,
        fix: 'Point "overrides" of this client at the overrides file itself.',
      );
      return null;
    }
    final String? text = _readText(path);
    if (text != null && _isBlank(text, file)) return _empty(file, path);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).load(path, displayPath: file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads overrides from [text]; [file] names it in diagnostics and tells
  /// JSON from YAML by its extension.
  OverrideSet? parse(String text, String file) {
    if (_isBlank(text, file)) return _empty(file, file);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).parse(text, file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads the overrides in an already loaded [document].
  OverrideSet read(SpecDocument document) =>
      OverrideDocumentReader(_diagnostics, document).read();

  /// The text of the file at [path], or null when it cannot be read; the
  /// spec loader then reports why.
  static String? _readText(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Whether [text] has nothing but whitespace, and for YAML comments and
  /// document markers: a file with no override yet.
  static bool _isBlank(String text, String file) {
    final json = p.extension(file).toLowerCase() == '.json';
    return text.split('\n').every((line) {
      final t = line.trim();
      return t.isEmpty ||
          (!json && (t.startsWith('#') || t == '---' || t == '...'));
    });
  }

  /// A set with no override, for a file that has no content.
  static OverrideSet _empty(String file, String path) => OverrideSet(
    SpecDocument(
      file: file,
      uri: p.toUri(p.normalize(p.absolute(path))),
      root: const {},
      spans: const {},
    ),
  );

  /// Reports what the spec loader said about the file as problems of the
  /// overrides file.
  void _forward(DiagnosticBag scratch) {
    for (final d in scratch.all) {
      _diagnostics.report(
        d.code == .positionsUnavailable ? d.code : .invalidOverride,
        d.message,
        severity: d.severity,
        file: d.file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
  }
}
