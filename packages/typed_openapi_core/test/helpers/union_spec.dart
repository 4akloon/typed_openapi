/// Spec text shared by the tests of unions with subsumed branches.
final class UnionSpec {
  const UnionSpec._();

  /// An OpenAPI 3.1 document up to the `schemas:` key, with one model
  /// (`Customer`) that union branches can refer to; a test appends its own
  /// schemas, indented by four spaces.
  static const head = '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Customer: {type: object, properties: {id: {type: string}}}
''';
}
