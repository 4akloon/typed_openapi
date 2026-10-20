import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

void main() {
  test('ids are unique and look like TOA123', () {
    final ids = [for (final code in DiagnosticCode.values) code.id];
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^TOA\d{3}$')));
    }
  });

  test('slugs are unique kebab-case', () {
    final slugs = [for (final code in DiagnosticCode.values) code.slug];
    expect(slugs.toSet(), hasLength(slugs.length));
    for (final slug in slugs) {
      expect(slug, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
  });
}
