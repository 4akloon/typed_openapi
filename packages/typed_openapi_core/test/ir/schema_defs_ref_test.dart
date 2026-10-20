import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  test(
    'a \$ref into the \$defs of a schema is a typed field, no diagnostics',
    () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Item:
      type: object
      required: [id]
      $defs:
        Id: {type: string, format: uuid}
        Tag:
          type: object
          required: [label]
          properties:
            label: {type: string}
      properties:
        id: {$ref: '#/components/schemas/Item/$defs/Id'}
        tag: {$ref: '#/components/schemas/Item/$defs/Tag'}
''');
      final (ir, _) = mapComponents(fixture, ['Item']);

      expect(fieldsOf(ir, 'Item'), ['id(id): String', 'tag(tag): Tag?']);
      expect(fixture.codes, isEmpty);
    },
  );

  test('a \$ref into \$defs at the document root resolves too', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
$defs:
  Tag:
    type: object
    required: [label]
    properties:
      label: {type: string}
components:
  schemas:
    Item:
      type: object
      properties:
        tag: {$ref: '#/$defs/Tag'}
''');
    final (ir, _) = mapComponents(fixture, ['Item']);

    expect(fieldsOf(ir, 'Item'), ['tag(tag): Tag?']);
    expect(fixture.codes, isEmpty);
  });
}
