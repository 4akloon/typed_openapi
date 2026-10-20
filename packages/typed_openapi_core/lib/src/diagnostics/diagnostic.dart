import 'package:source_span/source_span.dart';

import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'severity.dart';

/// Another place a [Diagnostic] is about, such as the override that
/// introduced the problem.
final class RelatedLocation {
  /// Creates a related location.
  const RelatedLocation({
    required this.message,
    this.file,
    this.pointer,
    this.span,
  });

  /// What this place has to do with the finding.
  final String message;

  /// The file, as shown to the user.
  final String? file;

  /// Where in [file] the place is.
  final JsonPointer? pointer;

  /// The source range in [file], when positions are known.
  final SourceSpan? span;

  /// `file:line:column`, `file` when only the file is known, or null.
  String? get location {
    final file = this.file;
    if (file == null) return null;
    final start = span?.start;
    return start == null ? file : '$file:${start.line + 1}:${start.column + 1}';
  }
}

/// One finding about a spec or the configuration.
///
/// Diagnostics are ordered by file, position, pointer, code and message, so
/// the same input always prints the same report.
final class Diagnostic implements Comparable<Diagnostic> {
  /// Creates a diagnostic.
  const Diagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.file,
    this.pointer,
    this.span,
    String? fix,
    this.backendFix,
    this.hints = const [],
    this.args = const [],
    this.related = const [],
  }) : _fix = fix;

  /// The stable code from the catalog.
  final DiagnosticCode code;

  /// The severity; may differ from [DiagnosticCode.defaultSeverity].
  final Severity severity;

  /// What is wrong, in one or two sentences.
  final String message;

  /// The file the finding is about, as shown to the user.
  final String? file;

  /// Where in [file] the finding is.
  final JsonPointer? pointer;

  /// The source range in [file], when positions are known.
  final SourceSpan? span;

  final String? _fix;

  /// What to change in the source to fix the finding, followed by the
  /// [hints]: a single hint as it is, several each after its preset's name
  /// (`nestjs: ...`). A fix that ends with a snippet on several lines is
  /// followed by the hints on lines of their own.
  String? get fix {
    if (hints.isEmpty) return _fix;
    final texts = hints.length == 1
        ? [hints.single.$2]
        : [for (final (preset, text) in hints) '$preset: $text'];
    final fix = _fix;
    if (fix != null && fix.contains('\n')) {
      return [fix.trimRight(), ...texts].join('\n');
    }
    return [?fix, ...texts].join(' ');
  }

  /// What to change at the source when the usual [fix] offers an override
  /// of the generator, which a backend team has no use for; see
  /// [forBackend].
  final String? backendFix;

  /// What a fix for a reader without the generator's config cannot say.
  static final RegExp _configWords = RegExp(
    r'override|typed_openapi\.yaml|severity|baseline|rules:',
    caseSensitive: false,
  );

  /// How to fix the finding in the code of a framework: the preset's name
  /// and the hint, one per preset of the clients that share the finding.
  final List<(String, String)> hints;

  /// Values from the spec that tell this finding from another of the same
  /// code at the same place, such as the name of a missing field; part of
  /// the baseline fingerprint, unlike [message].
  final List<String> args;

  /// Other places the finding is about.
  final List<RelatedLocation> related;

  /// The 1-based line of the finding, or null when the position is unknown.
  int? get line {
    final start = span?.start;
    return start == null ? null : start.line + 1;
  }

  /// The 1-based column of the finding, or null when the position is unknown.
  int? get column {
    final start = span?.start;
    return start == null ? null : start.column + 1;
  }

  /// This diagnostic for a reader who owns the spec, not the generator
  /// config: the fix is [backendFix], else the plain fix when it names
  /// no config (an override, the config file, a severity, a baseline, rules),
  /// else none. The [hints] stay.
  Diagnostic forBackend() {
    final plain = _fix;
    final own =
        backendFix ??
        (plain != null && !_configWords.hasMatch(plain) ? plain : null);
    return Diagnostic(
      code: code,
      severity: severity,
      message: message,
      file: file,
      pointer: pointer,
      span: span,
      fix: own,
      hints: hints,
      args: args,
      related: related,
    );
  }

  /// This diagnostic with [related] instead of its own related locations.
  Diagnostic withRelated(List<RelatedLocation> related) => Diagnostic(
    code: code,
    severity: severity,
    message: message,
    file: file,
    pointer: pointer,
    span: span,
    fix: _fix,
    backendFix: backendFix,
    hints: hints,
    args: args,
    related: related,
  );

  /// This diagnostic with [hints] instead of its own.
  Diagnostic withHints(List<(String, String)> hints) => Diagnostic(
    code: code,
    severity: severity,
    message: message,
    file: file,
    pointer: pointer,
    span: span,
    fix: _fix,
    backendFix: backendFix,
    hints: hints,
    args: args,
    related: related,
  );

  /// This diagnostic with [severity] instead of its own.
  Diagnostic withSeverity(Severity severity) => Diagnostic(
    code: code,
    severity: severity,
    message: message,
    file: file,
    pointer: pointer,
    span: span,
    fix: _fix,
    backendFix: backendFix,
    hints: hints,
    args: args,
    related: related,
  );

  /// `file:line:column`, `file` when only the file is known, or null.
  String? get location {
    final file = this.file;
    if (file == null) return null;
    final line = this.line;
    return line == null ? file : '$file:$line:$column';
  }

  @override
  int compareTo(Diagnostic other) {
    final byFile = (file ?? '').compareTo(other.file ?? '');
    if (byFile != 0) return byFile;
    final byOffset = (span?.start.offset ?? -1).compareTo(
      other.span?.start.offset ?? -1,
    );
    if (byOffset != 0) return byOffset;
    final byPointer = (pointer?.value ?? '').compareTo(
      other.pointer?.value ?? '',
    );
    if (byPointer != 0) return byPointer;
    final byCode = code.id.compareTo(other.code.id);
    if (byCode != 0) return byCode;
    return message.compareTo(other.message);
  }
}
