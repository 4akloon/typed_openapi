import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// A 3.1 spec whose `watch` streams events described by [schema] (the YAML
/// of a `schema`), under `components.schemas` as `Line` when it refers to it.
String _schemaSpec(String schema) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /watch:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: $schema}
components:
  schemas:
    Line: {type: string, minLength: 1}
''';

/// A 3.2 spec whose `watch` streams events with an `itemSchema` whose `data`
/// is [data] (the YAML of a schema).
String _itemSpec(String data) =>
    '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /watch:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
                properties:
                  data: $data
''';

/// The IR of [text] and the code of its API file.
(ClientIr, String) _build(String text) {
  final fixture = NormalizedFixture(text);
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.spec, fixture.client);
  final files = const ApiLibrary().files(ir, client: 'api');
  return (ir, files['api/t_api.dart']!);
}

void main() {
  group('an event schema that is a string of any shape is text', () {
    for (final (name, schema) in [
      ('a plain string', '{type: string}'),
      ('a nullable string', '{type: [string, "null"]}'),
      ('a string or null', '{anyOf: [{type: string}, {type: "null"}]}'),
      ('a string with a format', '{type: string, format: uuid}'),
      ('a referenced string', r"{$ref: '#/components/schemas/Line'}"),
      ('a string enum', '{type: string, enum: [start, stop]}'),
      ('a nullable string enum', '{type: [string, "null"], enum: [a, null]}'),
    ]) {
      test('$name decodes to String, not from JSON', () {
        final (ir, code) = _build(_schemaSpec(schema));
        expect(ir.groups.single.operations.single.events!.data, isNull);
        expect(code, contains('Stream<SseItem<String>>'));
        expect(code, contains('(m) => m.data,'));
        expect(code, isNot(contains('m.json')));
      });
    }

    test('a string enum declares no enum', () {
      final (ir, _) = _build(
        _schemaSpec('{type: string, enum: [start, stop]}'),
      );
      expect(ir.declarations, isEmpty);
    });
  });

  group('the data of an itemSchema', () {
    test('that is JSON holding a string is decoded as JSON', () {
      final (ir, code) = _build(
        _itemSpec(
          '{type: string, contentMediaType: application/json, '
          'contentSchema: {type: string}}',
        ),
      );
      expect(
        ir.groups.single.operations.single.events!.data,
        const CoreType(.string),
      );
      expect(code, contains('(m) => JsonReader.asString(m.json),'));
    });

    test('that is a plain string stays text', () {
      final (ir, code) = _build(_itemSpec('{type: string}'));
      expect(ir.groups.single.operations.single.events!.data, isNull);
      expect(code, contains('(m) => m.data,'));
    });
  });
}
