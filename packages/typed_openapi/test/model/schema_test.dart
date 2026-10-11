import 'package:test/test.dart';
import 'package:typed_openapi/src/model/schema.dart';

void main() {
  test('byWire finds a type by its wire name and cannot be modified', () {
    expect(SchemaType.byWire['integer'], SchemaType.integer);
    expect(
      () => SchemaType.byWire['x'] = SchemaType.string,
      throwsUnsupportedError,
    );
  });
}
