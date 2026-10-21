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

  test('the stage table matches the codes of the enum', () {
    int number(DiagnosticCode c) => int.parse(c.id.substring(3));
    String row(String stage) =>
        page.split('\n').singleWhere((l) => l.startsWith('| $stage |'));
    expect(row('Reading files'), contains('| TOA001-TOA022 |'));
    expect(row('Overrides'), contains('| TOA560, TOA800-TOA811 |'));
    expect(row('Baseline'), contains('| TOA820-TOA823 |'));
    expect(row('Generate'), contains('| TOA830-TOA835 |'));
    expect(row('Config'), contains('| TOA901-TOA904 |'));
    expect(row('Config codes'), contains('TOA901, TOA902, TOA903, TOA904'));
    final all = DiagnosticCode.values.map(number).toSet();
    // The prose list of the normalizer rules: each code must still exist.
    final listed = RegExp(r'TOA(\d{3})(?:-TOA(\d{3}))?').allMatches(
      row('Normalizer rules').split('|')[2],
    );
    for (final m in listed) {
      final from = int.parse(m.group(1)!);
      final to = int.parse(m.group(2) ?? m.group(1)!);
      expect(all.where((n) => n >= from && n <= to), isNotEmpty);
      expect(all, contains(from));
      expect(all, contains(to));
    }
  });
}
