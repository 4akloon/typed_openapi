import 'package:test/test.dart';
import 'package:typed_openapi_core/src/ir/schema_essence.dart';

void main() {
  test('annotations go at every depth of a schema', () {
    expect(
      SchemaEssence.of({
        'type': 'object',
        'description': 'd',
        'properties': {
          'a': {
            'type': 'array',
            'title': 't',
            'items': {'type': 'string', 'example': 'x'},
          },
        },
        'allOf': [
          {'type': 'object', 'deprecated': true},
        ],
      }),
      {
        'type': 'object',
        'properties': {
          'a': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'allOf': [
          {'type': 'object'},
        ],
      },
    );
  });

  test('a property named like an annotation stays', () {
    expect(
      SchemaEssence.of({
        'properties': {
          'description': {'type': 'string', 'description': 'd'},
        },
        'required': ['description'],
        'enum': ['title'],
      }),
      {
        'properties': {
          'description': {'type': 'string'},
        },
        'required': ['description'],
        'enum': ['title'],
      },
    );
  });

  test('null leaves a type list, and one type is the type', () {
    expect(
      SchemaEssence.of({
        'type': ['string', 'null'],
      }),
      {'type': 'string'},
    );
    expect(
      SchemaEssence.of({
        'type': ['string', 'integer', 'null'],
      }),
      {
        'type': ['string', 'integer'],
      },
    );
    expect(SchemaEssence.of({'nullable': true, 'type': 'string'}), {
      'type': 'string',
    });
  });

  test('a boolean schema is itself', () {
    expect(SchemaEssence.of(true), true);
  });
}
