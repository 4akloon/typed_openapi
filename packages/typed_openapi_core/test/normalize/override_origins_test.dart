import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/load/openapi_version.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';
import 'package:typed_openapi_core/src/normalize/normalizer.dart';
import 'package:typed_openapi_core/src/overrides/override_loader.dart';

void main() {
  List<Diagnostic> check(String spec, String overrides) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(spec, 'api.yaml')!;
    final set = OverrideLoader(bag).parse(overrides, 'api.overrides.yaml');
    Normalizer(bag).normalize(document, OpenApiVersion.v30, overrides: set);
    return bag.sorted;
  }

  test('a problem an override introduces points at the override', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
''',
      'schemas:\n  Pet: {format: binary}\n',
    );
    final binary = found.singleWhere(
      (d) => d.code == DiagnosticCode.binaryObject,
    );
    expect(binary.file, 'api.yaml');
    expect(
      binary.related.map((r) => (r.message, r.location, r.pointer?.value)),
      [
        (
          'Introduced by this override.',
          'api.overrides.yaml:2:17',
          '#/schemas/Pet/format',
        ),
      ],
    );
  });

  test('a problem the spec already had has no override location', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, format: binary, description: a}
    Tag: {type: object, format: binary}
''',
      'schemas:\n  Pet: {description: b}\n',
    );
    final binary = found.where((d) => d.code == DiagnosticCode.binaryObject);
    expect(binary, hasLength(2));
    expect(binary.every((d) => d.related.isEmpty), isTrue);
  });

  test('a problem elsewhere has no override location', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object}
    Tag: {type: object, properties: {name: {type: string, required: true}}}
''',
      'schemas:\n  Pet: {format: binary}\n',
    );
    final tag = found.singleWhere((d) => d.code == DiagnosticCode.boolRequired);
    expect(tag.related, isEmpty);
  });
}
