import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  test('patternProperties checks the keys that match', () {
    const schema = JsonSchema({
      'type': 'object',
      'patternProperties': {
        '^x-': {'type': 'string'},
      },
    });
    expect(schema.accepts({'x-a': 'one', 'other': 1}), isTrue);
    expect(schema.accepts({'x-a': 1}), isFalse);
  });

  test('propertyNames checks every key', () {
    const schema = JsonSchema({
      'type': 'object',
      'propertyNames': {'pattern': r'^[a-z]+$'},
    });
    expect(schema.accepts({'abc': 1}), isTrue);
    expect(schema.accepts({'abc': 1, 'A1': 2}), isFalse);
  });

  test('const compares JSON values', () {
    const schema = JsonSchema({
      'const': {
        'a': [1, 2],
      },
    });
    expect(
      schema.accepts({
        'a': [1, 2],
      }),
      isTrue,
    );
    expect(
      schema.accepts({
        'a': [2, 1],
      }),
      isFalse,
    );
  });

  test('minProperties rejects an empty object', () {
    const schema = JsonSchema({'type': 'object', 'minProperties': 1});
    expect(schema.accepts(<String, Object?>{}), isFalse);
    expect(schema.accepts({'a': 1}), isTrue);
  });

  test('enum compares lists and maps by value', () {
    const schema = JsonSchema({
      'enum': [
        [1, 2],
        {'a': 1},
      ],
    });
    expect(schema.accepts([1, 2]), isTrue);
    expect(schema.accepts({'a': 1}), isTrue);
    expect(schema.accepts([2, 1]), isFalse);
  });
}
