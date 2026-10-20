import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_tool/src/docs/diagnostic_source.dart';
import 'package:typed_openapi_tool/src/docs/diagnostics_page.dart';
import 'package:typed_openapi_tool/src/docs/extensions_page.dart';

void main() {
  late String page;

  setUpAll(() async {
    final docs = (await DiagnosticSource.load()).read();
    expect(docs.problems, isEmpty);
    page = DiagnosticsPage(docs.docs).render();
  });

  test('every code has an entry and a row in the index', () {
    for (final code in DiagnosticCode.values) {
      expect(page, contains('### ${code.id} `${code.slug}`'));
      expect(page, contains('| [${code.id}](#${code.docsAnchor}) |'));
    }
    expect(
      '### TOA'.allMatches(page).length,
      DiagnosticCode.values.length,
    );
  });

  test('the page counts its codes', () {
    expect(page, contains('all ${DiagnosticCode.values.length} codes'));
  });

  test('the anchors other guides link to still exist', () {
    expect(page, contains('\n## Severity and levels\n'));
    expect(page, contains('\n## Parse and resolve (TOA1xx)\n'));
  });

  test('a fixed code and a config code say so', () {
    expect(
      page,
      contains(
        '| [TOA001](#toa001-parse-error) | `parse-error` | error (fixed) |',
      ),
    );
    expect(page, contains('| `output-overlap` | error (config) |'));
    expect(page, contains('| `duplicate-key` | warning |'));
  });

  test('the entry of TOA458 is there, which the old table lacked', () {
    expect(page, contains('### TOA458 `union-json-type-shadowed`'));
  });

  test('the extensions page lists every extension with its example', () {
    final text = const ExtensionsPage(SpecExtensions.all).render();
    for (final extension in SpecExtensions.all) {
      expect(text, contains('## `${extension.key}`'));
      expect(text, contains(extension.example));
    }
    expect(text, contains('(diagnostics.md#toa351-enum-varnames-invalid)'));
  });
}
