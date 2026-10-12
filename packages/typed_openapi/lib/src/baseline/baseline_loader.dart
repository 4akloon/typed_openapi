import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import 'baseline.dart';

/// Reads a client's baseline file into a [Baseline].
///
/// Every problem goes to the [DiagnosticBag] given to the constructor, at
/// its position in the baseline file: a missing file is
/// `baseline-not-found`; text that cannot be read, a wrong `version` and a
/// bad entry are `invalid-baseline` errors (the entry is skipped); an
/// unknown key and a repeated fingerprint are `invalid-baseline` warnings.
final class BaselineLoader {
  /// Creates a loader that reports to [_diagnostics].
  const BaselineLoader(this._diagnostics);

  static final _fingerprint = RegExp(r'^[0-9a-f]{12}$');
  static const _rootKeys = {'version', 'entries'};
  static const _entryKeys = {
    'fingerprint',
    'code',
    'anchor',
    'message',
    'count',
  };

  final DiagnosticBag _diagnostics;

  /// Reads the baseline file at [path]; [displayPath] names it in
  /// diagnostics. Returns null when the file cannot be used at all.
  Baseline? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .baselineNotFound,
        'Baseline file $file does not exist.',
        file: file,
        fix:
            'Write it with `typed_openapi baseline create`, or fix '
            '"baseline" of this client in the config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .invalidBaseline,
        'Baseline path $file is a directory, not a file.',
        file: file,
        fix: 'Point "baseline" of this client at the baseline file itself.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .invalidBaseline,
        'Cannot read $file: ${e.message}.',
        file: file,
      );
      return null;
    }
    return parse(text, file, uri: p.toUri(p.normalize(p.absolute(path))));
  }

  /// Reads a baseline from [text]; [file] names it in diagnostics.
  Baseline? parse(String text, String file, {Uri? uri}) {
    if (text.split('\n').every(_isBlankLine)) return Baseline(file, const []);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).parse(text, file, uri: uri);
    for (final d in scratch.all) {
      _diagnostics.report(
        .invalidBaseline,
        d.message,
        severity: d.severity,
        file: d.file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    return document == null ? null : _read(document);
  }

  Baseline? _read(SpecDocument document) {
    final root = document.root;
    _unknownKeys(document, root, _rootKeys, .root);
    final version = root['version'];
    if (version != Baseline.version) {
      _invalid(
        document,
        switch (version) {
          _ when !root.containsKey('version') =>
            'The baseline has no "version".',
          int() =>
            'Unsupported baseline version $version; this tool reads '
                'version ${Baseline.version}.',
          _ =>
            'The baseline "version" must be the integer ${Baseline.version}.',
        },
        root.containsKey('version') ? JsonPointer.root.child('version') : .root,
        fix: 'Write the file again with `typed_openapi baseline create`.',
      );
      return null;
    }
    final list = root['entries'];
    final listPointer = JsonPointer.root.child('entries');
    if (list is! List<Object?>) {
      _invalid(
        document,
        '"entries" must be a list.',
        root.containsKey('entries') ? listPointer : .root,
      );
      return null;
    }
    final entries = <BaselineEntry>[];
    final seen = <String, JsonPointer>{};
    for (final (index, value) in list.indexed) {
      final at = listPointer.child(index);
      final entry = _entry(document, value, at);
      if (entry == null) continue;
      if (seen[entry.fingerprint] case final first?) {
        _diagnostics.report(
          .invalidBaseline,
          'This entry repeats the fingerprint of the entry at '
          '${first.value}; their counts add up.',
          severity: .warning,
          file: document.file,
          pointer: at,
          span: document.spanOf(at),
        );
      }
      seen.putIfAbsent(entry.fingerprint, () => at);
      entries.add(entry);
    }
    return Baseline(document.file, entries, source: document);
  }

  BaselineEntry? _entry(SpecDocument document, Object? value, JsonPointer at) {
    if (value is! Map<String, Object?>) {
      _invalid(document, 'An entry must be a mapping.', at);
      return null;
    }
    _unknownKeys(document, value, _entryKeys, at);
    final fingerprint = value['fingerprint'];
    if (fingerprint is! String || !_fingerprint.hasMatch(fingerprint)) {
      _invalid(
        document,
        'An entry needs a "fingerprint" of 12 lowercase hex digits; the '
        'entry is ignored.',
        value.containsKey('fingerprint') ? at.child('fingerprint') : at,
      );
      return null;
    }
    final count = value['count'] ?? 1;
    if (count is! int || count < 1) {
      _invalid(
        document,
        '"count" must be a positive integer; the entry is ignored.',
        at.child('count'),
      );
      return null;
    }
    String? text(String key) {
      final text = value[key];
      if (text == null || text is String) return text as String?;
      _invalid(
        document,
        '"$key" must be a string; it is ignored.',
        at.child(key),
      );
      return null;
    }

    return BaselineEntry(
      fingerprint: fingerprint,
      code: text('code'),
      anchor: text('anchor'),
      message: text('message'),
      count: count,
      pointer: at,
    );
  }

  void _unknownKeys(
    SpecDocument document,
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      _diagnostics.report(
        .invalidBaseline,
        'Unknown key "$key"; it is ignored.',
        severity: Severity.warning,
        file: document.file,
        pointer: at.child(key),
        span: document.spanOf(at.child(key)),
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  void _invalid(
    SpecDocument document,
    String message,
    JsonPointer at, {
    String? fix,
  }) {
    _diagnostics.report(
      .invalidBaseline,
      message,
      file: document.file,
      pointer: at,
      span: document.spanOf(at),
      fix: fix,
    );
  }

  static bool _isBlankLine(String line) {
    final t = line.trim();
    return t.isEmpty || t.startsWith('#') || t == '---' || t == '...';
  }
}
