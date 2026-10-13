import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec with [paths] (YAML under `paths:`) and [schemas] (under
/// `components.schemas`), in OpenAPI [version].
String _spec(String paths, {String schemas = '{}', String version = '3.1.0'}) =>
    '''
openapi: $version
info: {title: t, version: "1"}
paths:
$paths
components:
  schemas: $schemas
''';

/// The methods of the only group of [ir] by name.
Map<String, OperationIr> _methods(ClientIr ir) => {
  for (final o in ir.groups.single.operations) o.name: o,
};

/// The Dart type of the event data of [operation]: `String` for text.
String _data(ClientIr ir, OperationIr operation) =>
    operation.events!.data?.code(ir.nameOf) ?? 'String';

void main() {
  test('an event stream with a JSON schema is one method of its events', () {
    final fixture = IrFixture(
      _spec(
        r'''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {$ref: '#/components/schemas/Tick'}}}}
        "404": {description: no, content: {application/json: {schema: {type: string}}}}
''',
        schemas: '{Tick: {type: object, properties: {n: {type: integer}}}}',
      ),
    );
    final ir = fixture.build();
    final feed = _methods(ir)['feed']!;
    expect(_data(ir, feed), 'Tick');
    expect(feed.events!.reconnection, StreamReconnection.onRequest);
    expect(feed.successType, isNull);
    expect(
      [for (final r in feed.responses) r.kind],
      [
        BodyKind.eventStream,
        BodyKind.json,
      ],
    );
    expect(feed.errors, isA<SingleError>());
    expect(fixture.reportedOf(.eventStreamNotGenerated), isEmpty);
  });

  group('the data type', () {
    String dataOf(String media, {String schemas = '{}'}) {
      final fixture = IrFixture(
        _spec(
          '''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: $media}}
''',
          schemas: schemas,
          version: '3.2.0',
        ),
      );
      final ir = fixture.build();
      return _data(ir, _methods(ir)['feed']!);
    }

    test('is the contentSchema of itemSchema data, not the envelope', () {
      final fixture = IrFixture(
        _spec(
          r'''
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
                type: object
                properties:
                  event: {type: string}
                  data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Tick'}}
''',
          schemas: '{Tick: {type: object, properties: {n: {type: integer}}}}',
          version: '3.2.0',
        ),
      );
      final ir = fixture.build();
      expect(_data(ir, _methods(ir)['feed']!), 'Tick');
      expect([for (final d in ir.declarations) d.name], ['Tick']);
    });

    test('is text for itemSchema data that is a string', () {
      expect(
        dataOf('{itemSchema: {properties: {data: {type: string}}}}'),
        'String',
      );
    });

    test('is text, reported, when itemSchema has no data (TOA666)', () {
      final fixture = IrFixture(
        _spec('''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {itemSchema: {properties: {id: {type: string}}}}}}
''', version: '3.2.0'),
      );
      final ir = fixture.build();
      expect(_data(ir, _methods(ir)['feed']!), 'String');
      expect(
        fixture.reportedOf(.eventItemSchemaUnread).single.pointer?.value,
        '#/paths/~1feed/get/responses/200/content/text~1event-stream/'
        'itemSchema',
      );
    });

    test('is an item of an array schema, reported (TOA664)', () {
      final fixture = IrFixture(
        _spec(r'''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: array, items: {$ref: '#/components/schemas/Tick'}}}}}
''', schemas: '{Tick: {type: object, properties: {n: {type: integer}}}}'),
      );
      final ir = fixture.build();
      expect(_data(ir, _methods(ir)['feed']!), 'Tick');
      expect(fixture.reportedOf(.eventDataArrayItems), hasLength(1));
    });

    test('is text for a string schema and for no schema', () {
      expect(dataOf('{schema: {type: string}}'), 'String');
      expect(dataOf('{}'), 'String');
    });

    test('is text for an itemSchema that cannot be resolved', () {
      expect(
        dataOf(r"{itemSchema: {$ref: '#/components/schemas/Gone'}}"),
        'String',
      );
    });

    test('may be recursive', () {
      expect(
        dataOf(
          r"{schema: {$ref: '#/components/schemas/Node'}}",
          schemas:
              '{Node: {type: object, properties: {children: {type: array, '
              r"items: {$ref: '#/components/schemas/Node'}}}}}",
        ),
        'Node',
      );
    });
  });

  group('an operation that offers JSON and an event stream', () {
    const chat = r'''
  /chat:
    post:
      operationId: chat
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {$ref: '#/components/schemas/Reply'}}
            text/event-stream: {schema: {$ref: '#/components/schemas/Delta'}}
''';
    const schemas =
        '{Reply: {type: object, properties: {text: {type: string}}}, '
        'Delta: {type: object, properties: {part: {type: string}}}}';

    test('gets a second method for the events (TOA663)', () {
      final fixture = IrFixture(_spec(chat, schemas: schemas));
      final ir = fixture.build();
      final methods = _methods(ir);
      expect(methods.keys, ['chat', 'chatStream']);
      expect(methods['chat']!.events, isNull);
      expect(methods['chat']!.successes.single.kind, BodyKind.json);
      expect(_data(ir, methods['chatStream']!), 'Delta');
      expect(fixture.reportedOf(.eventStreamMethodAdded), hasLength(1));
      expect(fixture.reportedOf(.mediaTypesDropped), isEmpty);
    });

    test('names it with naming.stream_suffix', () {
      final fixture = IrFixture(
        _spec(chat, schemas: schemas),
        generation: const GenerationConfig(streamSuffix: 'Live'),
      );
      expect(_methods(fixture.build()).keys, ['chat', 'chatLive']);
    });

    test('names it apart from a method that has its name (TOA551)', () {
      final fixture = IrFixture(
        _spec(
          '''
$chat  /chat-stream:
    get:
      operationId: chatStream
      responses:
        "204": {description: none}
''',
          schemas: schemas,
        ),
      );
      expect(_methods(fixture.build()).keys, [
        'chat',
        'chatStream',
        'chatStream2',
      ]);
      expect(
        fixture.reportedOf(.nameCollision).single.message,
        contains('"chatStream2"'),
      );
    });

    test('of a POST does not reconnect, silently by default', () {
      final fixture = IrFixture(_spec(chat, schemas: schemas));
      final stream = _methods(fixture.build())['chatStream']!;
      expect(stream.events!.reconnection, StreamReconnection.off);
      expect(fixture.reportedOf(.eventStreamReconnectOff), isEmpty);
    });

    test(
      'of a POST is reported when the config asks to reconnect (TOA665)',
      () {
        final fixture = IrFixture(
          _spec(chat, schemas: schemas),
          generation: const GenerationConfig(streamReconnect: true),
        );
        final stream = _methods(fixture.build())['chatStream']!;
        expect(stream.events!.reconnection, StreamReconnection.off);
        final reported = fixture.reportedOf(.eventStreamReconnectOff).single;
        expect(reported.pointer?.value, '#/paths/~1chat/post');
        expect(reported.message, contains('applies to GET event streams only'));
        expect(reported.fix, contains('operations:'));
        expect(reported.fix, contains('reconnect: true'));
      },
    );
  });

  test('a GET reconnects by default with sse.reconnect in the config', () {
    final fixture = IrFixture(
      _spec('''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {}}}
        "204": {description: no events}
'''),
      generation: const GenerationConfig(streamReconnect: true),
    );
    final feed = _methods(fixture.build())['feed']!;
    expect(feed.events!.reconnection, StreamReconnection.on);
    expect([for (final r in feed.successes) r.status], ['200', '204']);
    expect(fixture.reportedOf(.eventStreamReconnectOff), isEmpty);
  });

  test('event streams with different data are not generated (TOA654)', () {
    final fixture = IrFixture(
      _spec('''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: object, properties: {a: {type: string}}}}}}
        "206": {description: part, content: {text/event-stream: {schema: {type: string}}}}
'''),
    );
    final ir = fixture.build();
    expect(ir.groups, isEmpty);
    expect(
      fixture.reportedOf(.eventStreamNotGenerated).single.pointer?.value,
      '#/paths/~1feed/get/responses',
    );
  });

  test('a secret in event data is a secret field of its model', () {
    final fixture = IrFixture(
      _spec(
        r'''
  /feed:
    get:
      operationId: feed
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {$ref: '#/components/schemas/Token'}}}}
''',
        schemas:
            '{Token: {type: object, properties: {value: {type: string, '
            'format: password}}}}',
      ),
    );
    final model = fixture.build().declarations.single as ModelDecl;
    expect(model.fields.single.sensitive, isTrue);
  });
}
