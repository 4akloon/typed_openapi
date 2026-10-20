import 'dart:io';
import 'dart:isolate';

import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../corpus/corpus_exception.dart';
import 'diagnostic_doc.dart';
import 'diagnostic_docs.dart';

/// Reads the doc comments of the `DiagnosticCode` enum.
///
/// The comment of an entry is meaning paragraphs, then `Example: ...` and
/// `Fix: ...` paragraphs that end with a full stop. The text is read, not
/// analysed, so the tool needs no `analyzer`.
final class DiagnosticSource {
  /// Creates a reader of the enum [text].
  const DiagnosticSource(this.text);

  /// The source text of the enum.
  final String text;

  static const _enumUri =
      'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
  static final _entry = RegExp(r'^  ([a-z][A-Za-z0-9]*)\(');
  static const _exampleLabel = 'Example: ';
  static const _fixLabel = 'Fix: ';

  /// Reads the enum of the core package.
  static Future<DiagnosticSource> load() async {
    final uri = await Isolate.resolvePackageUri(Uri.parse(_enumUri));
    if (uri == null) {
      throw const CorpusException(
        'The package typed_openapi_core cannot be found.',
      );
    }
    return DiagnosticSource(await File.fromUri(uri).readAsString());
  }

  /// Reads the comment of every entry.
  DiagnosticDocs read() {
    final byName = DiagnosticCode.values.asNameMap();
    final docs = <String, DiagnosticDoc>{};
    final problems = <String>[];
    final seen = <String>{};
    for (final (:name, :block) in _blocks()) {
      final code = byName[name];
      if (code == null) {
        problems.add('The source has an entry "$name" that the enum lacks.');
        continue;
      }
      seen.add(name);
      switch (_docOf(code, block)) {
        case (final doc?, _):
          docs[name] = doc;
        case (_, final problem?):
          problems.add(problem);
      }
    }
    for (final code in DiagnosticCode.values) {
      if (!seen.contains(code.name)) {
        problems.add('${code.id} has no doc comment.');
      }
    }
    return DiagnosticDocs(
      docs: [
        for (final code in DiagnosticCode.values) ?docs[code.name],
      ],
      problems: problems,
    );
  }

  List<({String name, List<String> block})> _blocks() {
    final entries = <({String name, List<String> block})>[];
    var block = <String>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('  const DiagnosticCode(')) break;
      if (line.startsWith('  ///')) {
        block.add(line.substring(5).replaceFirst(RegExp('^ '), ''));
      } else if (_entry.firstMatch(line) case final match?) {
        entries.add((name: match.group(1)!, block: block));
        block = [];
      } else {
        block = [];
      }
    }
    return entries;
  }

  (DiagnosticDoc?, String?) _docOf(DiagnosticCode code, List<String> block) {
    final id = code.id;
    if (block.isEmpty) return (null, '$id has no doc comment.');
    final meaning = <String>[];
    String? example;
    String? fix;
    for (final paragraph in _paragraphs(block)) {
      if (paragraph.startsWith(_exampleLabel)) {
        example = paragraph.substring(_exampleLabel.length);
      } else if (paragraph.startsWith(_fixLabel)) {
        fix = paragraph.substring(_fixLabel.length);
      } else {
        meaning.add(paragraph);
      }
    }
    final problem = switch ((meaning, example, fix)) {
      ([], _, _) => '$id has no meaning.',
      (_, null, _) => '$id has no "Example:" paragraph.',
      (_, _, null) => '$id has no "Fix:" paragraph.',
      (_, final e?, _) when !e.endsWith('.') =>
        '$id: "Example:" does not end with a full stop.',
      (_, _, final f?) when !f.endsWith('.') =>
        '$id: "Fix:" does not end with a full stop.',
      _ => null,
    };
    if (problem != null) return (null, problem);
    return (
      DiagnosticDoc(
        code: code,
        meaning: meaning,
        example: example!,
        fix: fix!,
      ),
      null,
    );
  }

  List<String> _paragraphs(List<String> block) {
    final paragraphs = <String>[];
    var lines = <String>[];
    void flush() {
      if (lines.isNotEmpty) paragraphs.add(lines.join(' '));
      lines = [];
    }

    for (final line in block) {
      if (line.trim().isEmpty) {
        flush();
      } else {
        lines.add(line.trimRight());
      }
    }
    flush();
    return paragraphs;
  }
}
