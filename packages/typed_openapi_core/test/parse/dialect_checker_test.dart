import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_core/src/load/openapi_version.dart';
import 'package:typed_openapi_core/src/parse/dialect_checker.dart';
import 'package:typed_openapi_core/src/parse/openapi_parser.dart';

import '../helpers/spec_fixture.dart';

void main() {
  DiagnosticBag check(String yaml, OpenApiVersion version) {
    final fixture = SpecFixture(yaml);
    OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(version);
    final bag = DiagnosticBag();
    DialectChecker(bag).check(fixture.index.features, version);
    return bag;
  }

  const schemas = '''
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: [string, "null"]}
    B: {type: string, nullable: true}
    C: {const: c}
    D: {const: d}
''';

  test('3.1 constructs in a 3.0 document: one warning per construct', () {
    final bag = check(schemas, .v30);
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type/1'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/C/const'),
    ]);
    expect(bag.all.first.severity, Severity.warning);
    expect(
      bag.all.last.message,
      '"const" is OpenAPI 3.1 (JSON Schema 2020-12), but the document '
      'declares 3.0; it is read as 3.1. It is used in 2 places; this is the '
      'first.',
    );
  });

  test('nullable in a 3.1 document is a warning', () {
    final bag = check(schemas, .v31);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.nullableAfterOpenApi30);
    expect(d.pointer?.value, '#/components/schemas/B/nullable');
    expect(d.line, 5);
  });

  test('3.2 constructs in older documents are infos', () {
    const yaml = '''
info: {title: t, version: "1"}
paths:
  /events:
    get:
      responses:
        "200":
          description: Events.
          content:
            text/event-stream:
              itemSchema: {type: object}
''';
    final bag = check(yaml, .v31);
    expect(bag.all.single.code, DiagnosticCode.openApi32InOlder);
    expect(bag.all.single.severity, Severity.info);
    expect(check(yaml, .v32).all, isEmpty);
  });

  test('a 3.2 document may use everything but nullable', () {
    final bag = check(schemas, .v32);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });
}
