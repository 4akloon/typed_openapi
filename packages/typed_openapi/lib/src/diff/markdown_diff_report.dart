import '../diagnostics/message_text.dart';
import 'api_change.dart';
import 'change_counts.dart';

/// The `markdown` report of `typed_openapi diff`, for a pull request
/// comment: a heading per client with the counts and a list of changes
/// per category, a fix in a fenced YAML block. Spec text is neutralised and
/// its Markdown characters escaped, so a spec cannot add a link or an image
/// to the comment.
final class MarkdownDiffReport {
  /// Creates the report.
  const MarkdownDiffReport();

  // The text never starts a line, so only the characters that mark up
  // inline text need an escape; `&` would start an entity.
  static final _special = RegExp(r'[\\`*_\[\]<>|~&]');
  static final _backticks = RegExp('`+');

  /// The report of the changes of each client, by client name.
  String format(Map<String, List<ApiChange>> clients) {
    final out = StringBuffer('## API changes\n');
    for (final name in clients.keys.toList()..sort()) {
      final changes = clients[name]!;
      final counts = changes.isEmpty
          ? 'no changes'
          : '${ChangeCounts(changes)}';
      out.write('\n### ${_text(name)}: $counts\n');
      for (final category in ChangeCategory.values) {
        final listed = changes.where((c) => c.category == category);
        if (listed.isEmpty) continue;
        out.write('\n**${category.label}**\n\n');
        for (final change in listed) {
          out.writeln('- ${_text(change.message)}');
          if (change.fix case final fix?) _writeFix(out, fix);
        }
      }
    }
    return '$out';
  }

  /// Writes [fix] in a fenced block whose fence is longer than any run of
  /// backticks in it, indented to belong to the list item.
  static void _writeFix(StringBuffer out, String fix) {
    final longest = _backticks
        .allMatches(fix)
        .fold(0, (n, m) => m[0]!.length > n ? m[0]!.length : n);
    final fence = '`' * (longest < 3 ? 3 : longest + 1);
    out.write('\n  Keep the old name with this override:\n\n  ${fence}yaml\n');
    for (final line in fix.split('\n')) {
      out.writeln('  ${MessageText.neutralise(line)}');
    }
    out.write('  $fence\n\n');
  }

  static String _text(String text) => MessageText.neutralise(
    text,
  ).replaceAllMapped(_special, (m) => '\\${m[0]}');
}
