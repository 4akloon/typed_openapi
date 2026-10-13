import 'package:source_span/source_span.dart';

import 'diagnostic_bag.dart';
import 'json_pointer.dart';
import 'message_text.dart';
import 'reporters.dart';
import 'severity.dart';

/// Formats diagnostics as GitHub Actions workflow commands, which GitHub
/// shows as annotations on the changed files.
///
/// One line per diagnostic: `::error`, `::warning` or `::notice` (for
/// info) with `file`, `line`, `col`, `endLine`, `endColumn` and a `title`
/// of code and name, then the message, the JSON pointer and the fix. A
/// related location is a `::notice` of its own. The summary line of the
/// text format ends the output. Values are escaped as the runner expects
/// (`%`, CR and LF, and in properties also `:` and `,`).
final class GitHubActionsReporter implements DiagnosticReporter {
  /// Creates a GitHub Actions reporter.
  const GitHubActionsReporter();

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...diagnostics.baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final out = StringBuffer();
    for (final (d, accepted) in listed) {
      final title =
          '${d.code.id} ${d.code.slug}${accepted ? ' (baselined)' : ''}';
      out.writeln(
        _command(
          accepted ? 'notice' : _kind(d.severity),
          title,
          d.file,
          d.span,
          [
            _text(d.message),
            if (d.pointer case final pointer?) 'at ${_text(pointer.value)}',
            if (d.fix case final fix?) 'fix: ${_text(fix)}',
          ],
        ),
      );
      for (final related in d.related) {
        out.writeln(
          _command(
            'notice',
            '$title (related)',
            related.file,
            related.span,
            [
              _text(related.message),
              if (related.pointer case final JsonPointer pointer)
                'at ${_text(pointer.value)}',
            ],
          ),
        );
      }
    }
    out.write(TextReporter.summary(diagnostics));
    return out.toString();
  }

  static String _command(
    String kind,
    String title,
    String? file,
    SourceSpan? span,
    List<String> lines,
  ) {
    final properties = [
      if (file != null) 'file=${_property(file)}',
      if (span != null) ...[
        'line=${span.start.line + 1}',
        'col=${span.start.column + 1}',
        'endLine=${span.end.line + 1}',
        'endColumn=${span.end.column + 1}',
      ],
      'title=${_property(title)}',
    ];
    return '::$kind ${properties.join(',')}::${_data(lines.join('\n'))}';
  }

  static String _kind(Severity severity) => switch (severity) {
    .error => 'error',
    .warning => 'warning',
    .info => 'notice',
  };

  /// [text] without the control characters the runner would print as they
  /// are; line breaks stay, `_data` escapes them.
  static String _text(String text) =>
      MessageText.neutralise(text, keepLineFeeds: true);

  static String _data(String value) => value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');

  static String _property(String value) =>
      _data(_text(value)).replaceAll(':', '%3A').replaceAll(',', '%2C');
}
