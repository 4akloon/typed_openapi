import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/model/document.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/security.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (OpenApiDocument, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final document = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(OpenApiVersion.v30);
    return (document, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a whole document', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets, version: "1.0", x-audience: public}
servers:
  - url: "https://{env}.example.com"
    variables:
      env: {default: api, enum: [api, staging]}
security:
  - bearer: []
tags:
  - {name: pets, description: Pets.}
paths:
  /pets:
    get: {responses: {"204": {description: No content}}}
  x-internal: true
components:
  schemas:
    Pet: {type: object}
  securitySchemes:
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    key: {type: apiKey, name: X-Key, in: header}
    oauth:
      type: oauth2
      flows:
        clientCredentials:
          tokenUrl: https://example.com/token
          scopes: {read: Read}
''');
    expect(fixture.diagnostics.all, isEmpty);
    expect(doc.version, OpenApiVersion.v30);
    expect(doc.info!.title, 'Pets');
    expect(doc.info!.extensions, {'x-audience': 'public'});
    expect(doc.servers.single.variables['env']!.enumValues, ['api', 'staging']);
    expect(doc.security!.single.schemes, {'bearer': <String>[]});
    expect(doc.tags.single.name, 'pets');
    expect(doc.paths.keys, ['/pets']);
    expect(doc.extensions, isEmpty);
    final components = doc.components!;
    expect(components.schemas['Pet'], isA<SchemaObject>());
    final schemes = components.securitySchemes;
    expect(inline(schemes['bearer']).type, SecuritySchemeType.http);
    expect(inline(schemes['key']).placement, ApiKeyLocation.header);
    final flow = inline(schemes['oauth']).flows!.clientCredentials!;
    expect(flow.scopes, {'read': 'Read'});
    expect(fixture.index.nodes[doc.location], same(doc));
  });

  test('missing required fields and unknown keys are reported; reading '
      'goes on', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets}
paths: {}
host: example.com
tags: [{description: No name.}]
components:
  securitySchemes:
    key: {type: apiKey}
''');
    expect(doc.info!.title, 'Pets');
    expect(doc.tags.single.description, 'No name.');
    // An apiKey scheme needs `name` and `in`.
    expect(fixture.codes, [
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.unknownKey,
    ]);
    expect(fixture.pointers, [
      '#/info',
      '#/components/securitySchemes/key',
      '#/components/securitySchemes/key',
      '#/tags/0',
      '#/host',
    ]);
  });

  test('notes 3.1 and 3.2 document-level constructs', () {
    final (_, fixture) = parse(r'''
openapi: 3.0.3
$self: https://example.com/api.yaml
info: {title: Pets, version: "1", summary: Pets API.}
jsonSchemaDialect: https://spec.openapis.org/oas/3.1/dialect/base
webhooks: {}
tags: [{name: cats, parent: pets, kind: nav}]
components:
  pathItems: {}
  mediaTypes:
    Json: {schema: {type: object}}
  securitySchemes:
    tls: {type: mutualTLS}
''');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.self,
      SpecFeature.jsonSchemaDialect,
      SpecFeature.webhooks,
      SpecFeature.infoSummary,
      SpecFeature.tagHierarchy,
      SpecFeature.componentPathItems,
      SpecFeature.componentMediaTypes,
      SpecFeature.mutualTls,
    });
  });

  test('parseFragment reads a node as the kind a reference expects', () {
    final fixture = SpecFixture('''
openapi: 3.0.3
x-shared:
  limit: {name: limit, in: query, schema: {type: integer}}
''');
    final parser = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    );
    final at = JsonPointer.parse('#/x-shared/limit');
    final limit = parser.parseFragment(at, RefKind.parameter)! as Parameter;
    expect(limit.name, 'limit');
    expect(
      parser.parseFragment(at.child('schema'), RefKind.schema),
      isA<SchemaObject>(),
    );
    expect(fixture.diagnostics.all, isEmpty);
  });
}
