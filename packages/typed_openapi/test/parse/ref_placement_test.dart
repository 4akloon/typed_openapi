import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  /// The diagnostics of reading [yaml] as a 3.1 document.
  List<Diagnostic> read(String yaml) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(yaml, 'api.yaml')!;
    SpecReader(bag).read(document, .v31);
    return bag.sorted;
  }

  group(r'a $ref where OpenAPI does not accept one', () {
    test('as an operation is ref-not-allowed, not unknown-key', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      $ref: resources/orders/list.yml
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refNotAllowed);
      expect(d.pointer?.value, r'#/paths/~1orders/get/$ref');
      expect(d.fix, contains('redocly bundle'));
    });

    test('instead of a string is ref-not-allowed, not invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info:
  title: Shop
  version: "1"
  description: {$ref: description.yml#/introduction}
paths:
  /orders:
    get:
      tags: [{$ref: tags.yml#/orders}]
''');
      expect(found.map((d) => (d.code, d.pointer?.value)), [
        (DiagnosticCode.refNotAllowed, '#/info/description'),
        (DiagnosticCode.refNotAllowed, '#/paths/~1orders/get/tags/0'),
      ]);
      expect(found.first.message, contains('expects a string here'));
    });

    test('a Reference Object where one is allowed is not reported', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200": {$ref: "#/components/responses/Ok"}
components:
  responses:
    Ok: {description: ok}
''');
      expect(found, isEmpty);
    });
  });

  group(r'an unquoted $ref: #/...', () {
    test('reads as a comment and gets a hint to quote it', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        kind:
          $ref: #/components/schemas/Kind
    Kind: {type: string}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refCommentedOut);
      expect(
        d.pointer?.value,
        r'#/components/schemas/Order/properties/kind/$ref',
      );
      expect(d.fix, contains("'#/components/schemas/Pet'"));
    });

    test('in a Reference Object as well', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200":
          $ref:   # /components/responses/Ok
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test('in a flow mapping, where the comment ends the line', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order: {$ref: #/components/schemas/Base
      }
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test(r'an empty $ref without a comment stays invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      $ref:
''');
      expect(found.single.code, DiagnosticCode.invalidValue);
    });
  });

  group('a YAML merge key', () {
    test('in an object is yaml-merge-key, not unknown-key', () {
      final found = read('''
openapi: 3.1.0
info: {title: Shop, version: "1"}
x-defaults: &defaults {summary: List}
paths:
  /orders:
    get:
      <<: *defaults
      responses: {}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.yamlMergeKey);
      expect(d.pointer?.value, '#/paths/~1orders/get/<<');
      expect(d.fix, 'Write the keys out.');
    });

    test('in a map of named entries is reported and left out', () {
      final found = read('''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    <<: {Base: {type: object}}
    Order: {type: object}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.yamlMergeKey);
      expect(d.pointer?.value, '#/components/schemas/<<');
    });
  });
}
