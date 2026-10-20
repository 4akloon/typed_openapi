import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'diagnostic_area.dart';
import 'diagnostic_doc.dart';
import 'diagnostics_intro.dart';

/// Renders `doc/diagnostics.md` from the doc comments of the codes.
final class DiagnosticsPage {
  /// Creates the page for [docs], one per code.
  const DiagnosticsPage(this.docs);

  /// The documentation of every code, in the order of the enum.
  final List<DiagnosticDoc> docs;

  /// The Markdown text of the page.
  String render() {
    final intro = DiagnosticsIntro(docs.length);
    final buffer = StringBuffer(intro.opening);
    for (final area in DiagnosticArea.values) {
      final inArea = [
        for (final doc in docs)
          if (DiagnosticArea.of(doc.code) == area) doc,
      ];
      if (inArea.isNotEmpty) _writeArea(buffer, area, inArea);
    }
    buffer.write(intro.closing);
    return buffer.toString();
  }

  void _writeArea(
    StringBuffer buffer,
    DiagnosticArea area,
    List<DiagnosticDoc> inArea,
  ) {
    buffer
      ..writeln('## ${area.heading}')
      ..writeln()
      ..writeln(area.summary)
      ..writeln()
      ..writeln('| Code | Slug | Default |')
      ..writeln('| --- | --- | --- |');
    for (final doc in inArea) {
      final code = doc.code;
      buffer.writeln(
        '| [${code.id}](#${code.docsAnchor}) | `${code.slug}` | '
        '${_default(code)} |',
      );
    }
    buffer.writeln();
    for (final doc in inArea) {
      _writeEntry(buffer, doc);
    }
  }

  void _writeEntry(StringBuffer buffer, DiagnosticDoc doc) {
    final code = doc.code;
    buffer
      ..writeln('### ${code.id} `${code.slug}`')
      ..writeln()
      ..writeln('Default: ${_default(code)}.')
      ..writeln();
    for (final paragraph in doc.meaning) {
      buffer
        ..writeln(paragraph)
        ..writeln();
    }
    buffer
      ..writeln('**Example.** ${doc.example}')
      ..writeln()
      ..writeln('**Fix.** ${doc.fix}')
      ..writeln();
  }

  static String _default(DiagnosticCode code) {
    final level = code.defaultSeverity.name;
    if (DiagnosticCode.configCodes.contains(code)) return '$level (config)';
    if (DiagnosticCode.fixedCodes.contains(code)) return '$level (fixed)';
    return level;
  }
}
