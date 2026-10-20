import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema: {$ref: '#/components/schemas/UploadForm'}
      responses: {"204": {description: ok}}
components:
  schemas:
    UploadForm:
      type: object
      properties:
        file: {type: string, format: binary}
''';

void main() {
  test('a name override of a multipart-only schema says it is not used', () {
    final fixture = IrFixture(
      _spec,
      overrides: '''
schemas:
  UploadForm: {name: PhotoUpload}
''',
    );
    final ir = fixture.build();
    expect(ir.groups.single.operations.single.partsName, 'UploadRequest');
    final [notice] = fixture.reportedOf(.overrideUnchanged);
    expect(notice.file, 'o.yaml');
    expect(notice.pointer?.value, '#/schemas/UploadForm/name');
    expect(
      notice.message,
      'The name of this override has no effect on the multipart body that '
      'uses the schema: its class of parts is named after the operation.',
    );
  });

  test('a multipart schema without a name override reports nothing', () {
    final fixture = IrFixture(_spec);
    fixture.build();
    expect(fixture.reportedOf(.overrideUnchanged), isEmpty);
  });
}
