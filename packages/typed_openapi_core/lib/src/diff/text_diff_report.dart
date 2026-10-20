import '../diagnostics/message_text.dart';
import 'api_change.dart';
import 'change_counts.dart';

/// The `text` report of `typed_openapi diff`: per client a line with the
/// counts, then a line per change and the lines of its fix. Spec text is
/// neutralised, as in the diagnostics report.
final class TextDiffReport {
  /// Creates the report.
  const TextDiffReport();

  /// The report of the changes of each client, by client name.
  String format(Map<String, List<ApiChange>> clients) {
    final out = StringBuffer();
    for (final name in clients.keys.toList()..sort()) {
      final changes = clients[name]!;
      final client = MessageText.neutralise(name);
      if (changes.isEmpty) {
        out.writeln('$client: no changes.');
        continue;
      }
      out.writeln('$client: ${ChangeCounts(changes)}.');
      for (final change in changes) {
        out.writeln(
          '  ${change.category.label}: '
          '${MessageText.neutralise(change.message)}',
        );
        if (change.fix case final fix?) {
          out.writeln('    Keep the old name with this override:');
          for (final line in fix.split('\n')) {
            out.writeln('      ${MessageText.neutralise(line)}');
          }
        }
      }
    }
    return '$out';
  }
}
