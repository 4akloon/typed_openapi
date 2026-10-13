import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

String specOf(String mediaType) =>
    r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          MEDIA: {$ref: '#/components/mediaTypes/Missing'}
      responses: {"204": {description: ok}}
'''
        .replaceAll('MEDIA', mediaType);

void main() {
  group('a media type of a request body that is an unresolved ref', () {
    for (final (name, mediaType, kind) in [
      ('multipart', 'multipart/form-data', BodyKind.multipart),
      ('form', 'application/x-www-form-urlencoded', BodyKind.form),
    ]) {
      test('is reported once (TOA101) and does not throw for $name', () {
        final fixture = IrFixture(specOf(mediaType));
        final ir = build(fixture);
        final body = ir.groups.single.operations.single.body!;
        expect(body.kind, kind);
        expect(body.encoding, isEmpty);
        expect(body.parts, isNull);
        expect(body.type, isNull);
        expect(
          fixture.diagnostics.all.where(
            (d) => d.code == DiagnosticCode.unresolvedRef,
          ),
          hasLength(1),
        );
        expect(fixture.reported, isEmpty);
      });
    }
  });

  test(
    'a response and a parameter with an unresolved media type do not throw',
    () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: read
      tags: [t]
      parameters:
        - name: filter
          in: query
          content:
            application/json: {$ref: '#/components/mediaTypes/Missing'}
      responses:
        "200":
          description: ok
          content:
            multipart/form-data: {$ref: '#/components/mediaTypes/Missing'}
''');
      expect(() => build(fixture), returnsNormally);
    },
  );
}
