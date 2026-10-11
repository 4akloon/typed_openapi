import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';

void main() {
  (OpenApiVersion?, DiagnosticBag) detect(String yaml) {
    final bag = DiagnosticBag();
    final doc = SpecLoader(bag).parse(yaml, 'api.yaml')!;
    return (OpenApiVersionDetector(bag).detect(doc), bag);
  }

  test('reads 3.0, 3.1 and 3.2 regardless of the patch version', () {
    expect(detect('openapi: 3.0.4').$1, OpenApiVersion.v30);
    expect(detect('openapi: 3.1.0').$1, OpenApiVersion.v31);
    expect(detect('openapi: "3.2.1"').$1, OpenApiVersion.v32);
  });

  test('accepts an unquoted YAML number such as 3.0 with a warning', () {
    final (version, bag) = detect('openapi: 3.0');
    expect(version, OpenApiVersion.v30);
    expect(bag.all.single.code, DiagnosticCode.openApiVersionNotString);
    expect(bag.all.single.pointer?.value, '#/openapi');
  });

  test('does not throw on a minor version too large for an int', () {
    final (version, bag) = detect('openapi: "3.99999999999999999999"');
    expect(version, isNull);
    expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
  });

  test('reads a newer 3.x minor as 3.2 with a warning', () {
    final (version, bag) = detect('openapi: 3.3.0');
    expect(version, OpenApiVersion.v32);
    expect(bag.all.single.code, DiagnosticCode.unknownOpenApiMinorVersion);
  });

  test('rejects Swagger 2.0', () {
    final (version, bag) = detect('swagger: "2.0"');
    expect(version, isNull);
    expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
    expect(bag.all.single.pointer?.value, '#/swagger');
    expect(bag.all.single.span, isNotNull);
  });

  test('reports a missing openapi field', () {
    final (version, bag) = detect('info: {title: x}');
    expect(version, isNull);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });
}
