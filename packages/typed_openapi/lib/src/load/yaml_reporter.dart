import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import 'yaml_frame.dart';

/// Reports what the composer finds in one file.
final class YamlReporter {
  /// Creates a reporter that writes to [_diagnostics] for [_file]; with
  /// [json], a duplicate key is never an error.
  const YamlReporter(this._diagnostics, this._file, {required bool json})
    : _json = json;

  final DiagnosticBag _diagnostics;
  final String _file;
  final bool _json;

  /// Reports [code] with [message] at [span] of the file.
  void report(
    DiagnosticCode code,
    String message, {
    required SourceSpan span,
    JsonPointer? pointer,
    Severity? severity,
    String? fix,
  }) {
    _diagnostics.report(
      code,
      message,
      severity: severity,
      file: _file,
      pointer: pointer,
      span: span,
      fix: fix,
    );
  }

  /// Reports a warning of the YAML parser.
  void parserWarning(String message, SourceSpan span) {
    report(.yamlWarning, message, span: span);
  }

  /// Reports that a key of the mapping at [mapping] repeats [earlier].
  void duplicateKey(
    JsonPointer mapping,
    String text,
    YamlKey earlier,
    Object? value,
    SourceSpan span,
  ) {
    final yamlEqual = earlier.value == value;
    report(
      .duplicateKey,
      yamlEqual
          ? 'Duplicate mapping key "$text"; the last value is used.'
          : 'Keys ${earlier.span.text} and ${span.text} are the same key '
                '"$text" in JSON; the last value is used.',
      // YAML forbids equal keys; JSON leaves them to the reader.
      severity: yamlEqual && !_json ? .error : null,
      pointer: mapping.child(text),
      span: span,
      fix: 'Remove one of the keys.',
    );
  }

  /// Reports that the key [text] of the mapping at [mapping] is null in YAML.
  void nullKey(JsonPointer mapping, String text, SourceSpan span) {
    report(
      .nullKey,
      text.isEmpty
          ? 'This mapping key is empty, which YAML reads as null; it is read '
                'as the empty string.'
          : 'The mapping key $text is null in YAML; it is read as the string '
                '"$text".',
      pointer: mapping.child(text),
      span: span,
      fix: 'Quote the key: "$text".',
    );
  }

  /// Reports that a key of the mapping at [mapping] is a collection.
  void nonStringKey(JsonPointer mapping, SourceSpan span) {
    report(
      .nonStringKey,
      'A mapping key must be a string, not a collection; the entry is '
      'ignored.',
      pointer: mapping,
      span: span,
      fix: 'Write the key as a plain or quoted string.',
    );
  }

  /// Reports an alias at [pointer] to a node inside such a key.
  void aliasInsideNonStringKey(JsonPointer pointer, SourceSpan span) {
    report(
      .nonStringKey,
      'This alias refers to a node inside a mapping key that is not a '
      'string; it is read as null.',
      pointer: pointer,
      span: span,
      fix: 'Anchor the node outside the key.',
    );
  }
}
