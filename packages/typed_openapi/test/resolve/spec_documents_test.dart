import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';

void main() {
  test('a URI that is not a valid file path is a missing file', () {
    final bag = DiagnosticBag();
    final root = SpecLoader(bag).parse(
      'openapi: 3.1.0',
      'specs/api.yaml',
      uri: Uri.parse('file:///project/specs/api.yaml'),
    )!;
    final documents = SpecDocuments(SpecLoader(bag), root);
    final bad = Uri.parse('file:///project/specs/%FF.yaml');
    expect(documents[bad], isNull);
    expect(documents.exists(bad), isFalse);
    expect(documents.displayPath(bad), '$bad');
    expect(bag.all, isEmpty);
  });
}
