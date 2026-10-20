import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'generated_notice.dart';

/// Renders `doc/extensions.md` from the extension registry.
final class ExtensionsPage {
  /// Creates the page for [extensions].
  const ExtensionsPage(this.extensions);

  /// The `x-` keys the tool reads.
  final List<SpecExtension> extensions;

  /// The Markdown text of the page.
  String render() {
    final buffer = StringBuffer(GeneratedNotice.markdown)
      ..writeln('# Extensions reference')
      ..writeln()
      ..writeln(
        'Vendor extensions (`x-` keys) that `typed_openapi` reads from a '
        'spec. Any other `x-` key is kept and ignored. This page is '
        'generated from the extension registry of the tool.',
      )
      ..writeln();
    for (final extension in extensions) {
      _write(buffer, extension);
    }
    return buffer.toString();
  }

  void _write(StringBuffer buffer, SpecExtension extension) {
    buffer
      ..writeln('## `${extension.key}`')
      ..writeln()
      ..writeln('Applies to ${extension.appliesTo}.')
      ..writeln()
      ..writeln(extension.effect)
      ..writeln()
      ..writeln('```yaml')
      ..writeln(extension.example)
      ..writeln('```')
      ..writeln();
    if (extension.diagnostics.isEmpty) return;
    final links = [
      for (final code in extension.diagnostics)
        '[${code.id}](diagnostics.md#${code.docsAnchor})',
    ];
    buffer
      ..writeln('Reported by ${links.join(', ')}.')
      ..writeln();
  }
}
