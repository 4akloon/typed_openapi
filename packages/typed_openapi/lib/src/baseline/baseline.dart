import 'dart:convert';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import '../load/spec_document.dart';
import 'fingerprints.dart';

/// One accepted finding of a baseline file.
///
/// Only [fingerprint] and [count] take part in matching; [code], [anchor]
/// and [message] are there for the person who reads the file.
final class BaselineEntry {
  /// Creates an entry.
  const BaselineEntry({
    required this.fingerprint,
    this.code,
    this.anchor,
    this.message,
    this.count = 1,
    this.pointer = JsonPointer.root,
  });

  /// The fingerprint of the accepted diagnostics (see [Fingerprints]).
  final String fingerprint;

  /// The code of the diagnostics, such as `TOA201`.
  final String? code;

  /// Where they are (see [Fingerprints.anchorOf]).
  final String? anchor;

  /// The message of the first of them when the entry was written.
  final String? message;

  /// How many diagnostics with [fingerprint] the entry accepts.
  final int count;

  /// Where the entry is in its baseline file.
  final JsonPointer pointer;

  BaselineEntry _withCount(int count) => BaselineEntry(
    fingerprint: fingerprint,
    code: code,
    anchor: anchor,
    message: message,
    count: count,
    pointer: pointer,
  );
}

/// What a baseline does to a client's diagnostics.
final class BaselineMatch {
  /// Creates a match.
  const BaselineMatch({
    required this.shown,
    required this.baselined,
    required this.stale,
  });

  /// Diagnostics no entry accepts, in report order.
  final List<Diagnostic> shown;

  /// Diagnostics an entry accepts, in report order.
  final List<Diagnostic> baselined;

  /// Entries that accept more diagnostics than there are, with how many
  /// diagnostics they still match.
  final List<(BaselineEntry, int)> stale;
}

/// A client's baseline: the diagnostics it has accepted, so that `check`
/// fails only on new ones (R2.3).
///
/// The file is YAML with `version: 1` and a list of `entries`, sorted by
/// code, anchor and fingerprint; see [toYaml].
final class Baseline {
  /// Creates a baseline named [file] in reports; [source] is the document
  /// it was read from, for positions.
  const Baseline(this.file, this.entries, {SpecDocument? source})
    : _source = source;

  /// A baseline that accepts every error and warning in [diagnostics]
  /// except those of [DiagnosticCode.fixedCodes]; a baseline never hides
  /// those, nor an info.
  factory Baseline.of(
    String file,
    Iterable<Diagnostic> diagnostics,
    Fingerprints fingerprints,
  ) {
    final entries = <String, BaselineEntry>{};
    for (final diagnostic in diagnostics.toList()..sort()) {
      if (!_acceptable(diagnostic)) continue;
      final fingerprint = fingerprints.of(diagnostic);
      final entry = entries[fingerprint];
      entries[fingerprint] = entry == null
          ? BaselineEntry(
              fingerprint: fingerprint,
              code: diagnostic.code.id,
              anchor: fingerprints.anchorOf(diagnostic),
              message: diagnostic.message,
            )
          : entry._withCount(entry.count + 1);
    }
    return Baseline(file, _sorted(entries.values));
  }

  /// The version of the file format this tool writes and reads.
  static const version = 1;

  /// The baseline file as diagnostics name it.
  final String file;

  /// The entries, in file order.
  final List<BaselineEntry> entries;

  final SpecDocument? _source;

  /// The source range of [pointer] in the file, if known.
  SourceSpan? spanOf(JsonPointer pointer) => _source?.spanOf(pointer);

  /// Splits [diagnostics] into those the entries accept and the rest.
  ///
  /// An entry accepts up to its count of diagnostics with its fingerprint,
  /// in report order; an info and a diagnostic of
  /// [DiagnosticCode.fixedCodes] are never accepted.
  BaselineMatch match(
    Iterable<Diagnostic> diagnostics,
    Fingerprints fingerprints,
  ) {
    final allowed = <String, int>{};
    for (final entry in entries) {
      allowed[entry.fingerprint] =
          (allowed[entry.fingerprint] ?? 0) + entry.count;
    }
    final used = <String, int>{};
    final shown = <Diagnostic>[];
    final baselined = <Diagnostic>[];
    for (final diagnostic in diagnostics.toList()..sort()) {
      final fingerprint = _acceptable(diagnostic)
          ? fingerprints.of(diagnostic)
          : null;
      final count = used[fingerprint] ?? 0;
      if (fingerprint != null && count < (allowed[fingerprint] ?? 0)) {
        used[fingerprint] = count + 1;
        baselined.add(diagnostic);
      } else {
        shown.add(diagnostic);
      }
    }
    final stale = <(BaselineEntry, int)>[];
    for (final entry in entries) {
      final left = used[entry.fingerprint] ?? 0;
      final matched = left < entry.count ? left : entry.count;
      used[entry.fingerprint] = left - matched;
      if (matched < entry.count) stale.add((entry, matched));
    }
    return BaselineMatch(shown: shown, baselined: baselined, stale: stale);
  }

  /// This baseline without what [match] found stale: an entry that matches
  /// nothing is removed, one that matches fewer diagnostics than its count
  /// gets that number. Nothing is added.
  Baseline pruned(BaselineMatch match) {
    final matched = {
      for (final (entry, count) in match.stale) entry: count,
    };
    final kept = <BaselineEntry>[];
    for (final entry in entries) {
      final count = matched[entry];
      if (count == null) {
        kept.add(entry);
      } else if (count > 0) {
        kept.add(entry._withCount(count));
      }
    }
    return Baseline(file, kept);
  }

  /// The baseline file's text: a comment, `version` and the entries sorted
  /// by code, anchor and fingerprint. Strings are written as JSON strings,
  /// which YAML reads unchanged.
  String toYaml() {
    final out = StringBuffer()
      ..writeln('# Diagnostics accepted for this client: typed_openapi check')
      ..writeln('# hides them. Written by `typed_openapi baseline create`;')
      ..writeln('# `typed_openapi baseline prune` removes stale entries.')
      ..writeln('version: $version');
    final sorted = _sorted(entries);
    if (sorted.isEmpty) {
      out.writeln('entries: []');
      return out.toString();
    }
    out.writeln('entries:');
    for (final entry in sorted) {
      out.writeln('  - fingerprint: ${jsonEncode(entry.fingerprint)}');
      for (final (key, value) in [
        ('code', entry.code),
        ('anchor', entry.anchor),
        ('message', entry.message),
      ]) {
        if (value != null) out.writeln('    $key: ${jsonEncode(value)}');
      }
      if (entry.count != 1) out.writeln('    count: ${entry.count}');
    }
    return out.toString();
  }

  /// Whether a baseline may accept [diagnostic]: an error or a warning of a
  /// code that is not fixed. An info does not fail a check, so it is always
  /// shown.
  static bool _acceptable(Diagnostic diagnostic) =>
      diagnostic.severity != Severity.info &&
      !DiagnosticCode.fixedCodes.contains(diagnostic.code);

  static List<BaselineEntry> _sorted(Iterable<BaselineEntry> entries) =>
      entries.toList()..sort((a, b) {
        final byCode = (a.code ?? '').compareTo(b.code ?? '');
        if (byCode != 0) return byCode;
        final byAnchor = (a.anchor ?? '').compareTo(b.anchor ?? '');
        if (byAnchor != 0) return byAnchor;
        return a.fingerprint.compareTo(b.fingerprint);
      });
}
