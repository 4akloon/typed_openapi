import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// An OpenAPI 3.2 spec whose `GET /feed` (`watch`) streams events of the
/// `itemSchema` [item] (YAML, indented under `itemSchema:`), with [schemas]
/// and, when [extra] is given, a second operation `GET /extra` returning it.
String _spec(String item, {String schemas = '{}', String? extra}) =>
    '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: watch
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
$item
${extra == null ? '' : '''
  /extra:
    get:
      operationId: extra
      responses:
        "200": {description: ok, content: {application/json: {schema: $extra}}}
'''}components:
  schemas: $schemas
''';

const _delta =
    '{type: object, properties: {text: {type: string}, key: {type: string, '
    'format: password}}}';

/// The union of the only method of [fixture].
EventUnionIr _union(ClientIr ir) => ir.groups.single.operations
    .firstWhere((o) => o.name == 'watch')
    .events!
    .union!;

/// The event, class name and data of each variant of [union].
List<String> _variants(ClientIr ir, EventUnionIr union) => [
  for (final v in union.variants)
    '${v.event} ${v.name} '
        '${v.hasData ? v.data?.code(ir.nameOf) ?? 'String' : '-'}',
];

void main() {
  test('a oneOf of events with constant names is a union by event', () {
    final fixture = IrFixture(
      _spec(
        r'''
                oneOf:
                  - properties:
                      event: {const: delta}
                      data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Delta'}}
                  - properties: {event: {enum: [note]}, data: {type: string}}
                  - properties: {event: {const: done}}
                  - properties: {event: {const: stop}, data: {type: 'null'}}''',
        schemas: '{Delta: $_delta}',
      ),
    );
    final ir = fixture.build();
    final union = _union(ir);
    expect(union.name, 'WatchEvent');
    expect(union.unknownName, 'WatchEventUnknown');
    expect(_variants(ir, union), [
      'delta WatchEventDelta Delta',
      'note WatchEventNote String',
      'done WatchEventDone -',
      'stop WatchEventStop -',
    ]);
    expect(union.unknownSensitive, isTrue);
    expect(fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread), isEmpty);
  });

  test('anyOf is read like oneOf', () {
    final fixture = IrFixture(
      _spec('''
                anyOf:
                  - properties: {event: {const: a}, data: {type: string}}
                  - properties: {event: {const: b}}'''),
    );
    final ir = fixture.build();
    expect(_variants(ir, _union(ir)), [
      'a WatchEventA String',
      'b WatchEventB -',
    ]);
  });

  test('a branch without a constant event name makes the data text', () {
    final fixture = IrFixture(
      _spec(
        '''
                oneOf:
                  - properties: {event: {const: a}, data: {type: string}}
                  - properties: {event: {type: string}, data: {type: string}}''',
      ),
    );
    final feed = fixture.build().groups.single.operations.single;
    expect(feed.events!.union, isNull);
    expect(feed.events!.data, isNull);
    expect(
      fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread),
      hasLength(1),
    );
  });

  test('a repeated event name keeps the first branch (TOA667)', () {
    final fixture = IrFixture(
      _spec('''
                oneOf:
                  - properties: {event: {const: a}, data: {type: string}}
                  - properties: {event: {const: a}, data: {type: integer}}'''),
    );
    final ir = fixture.build();
    expect(_variants(ir, _union(ir)), ['a WatchEventA String']);
    expect(
      fixture
          .reportedOf(DiagnosticCode.eventNameDuplicate)
          .single
          .pointer
          ?.value,
      '#/paths/~1feed/get/responses/200/content/text~1event-stream/'
      'itemSchema/oneOf/1',
    );
  });

  test('hostile event names get safe, distinct class names', () {
    final fixture = IrFixture(
      _spec('''
                oneOf:
                  - {properties: {event: {const: "-"}}}
                  - {properties: {event: {const: "*/"}}}
                  - {properties: {event: {const: unknown}}}
                  - {properties: {event: {const: Delta}}}
                  - {properties: {event: {const: delta}}}
                  - {properties: {event: {const: class}}}
                  - {properties: {event: {const: "a b"}}}'''),
    );
    final ir = fixture.build();
    expect(
      [for (final v in _union(ir).variants) v.name],
      [
        'WatchEventEvent1',
        'WatchEventEvent2',
        'WatchEventUnknown2',
        'WatchEventDelta',
        'WatchEventDelta2',
        'WatchEventClass',
        'WatchEventAB',
      ],
    );
    expect(_union(ir).unknownName, 'WatchEventUnknown');
    expect(
      fixture.reportedOf(DiagnosticCode.eventNameUnrepresentable),
      hasLength(2),
    );
    expect(fixture.reportedOf(DiagnosticCode.nameCollision), hasLength(2));
  });

  test('the union is named after the models (TOA551)', () {
    final fixture = IrFixture(
      _spec(
        '''
                oneOf:
                  - {properties: {event: {const: a}}}''',
        schemas:
            '{WatchEvent: {type: object, properties: {id: {type: string}}}}',
        extra: r"{$ref: '#/components/schemas/WatchEvent'}",
      ),
    );
    final ir = fixture.build();
    expect(_union(ir).name, 'WatchEvent2');
    expect(ir.declarations.map((d) => d.name), contains('WatchEvent'));
  });

  test('a secret in event data is a secret variant', () {
    final fixture = IrFixture(
      _spec(
        '''
                oneOf:
                  - properties: {event: {const: token}, data: {type: string, format: password}}
                  - properties: {event: {const: ping}, data: {type: string}}''',
      ),
    );
    final union = _union(fixture.build());
    expect([for (final v in union.variants) v.sensitive], [true, false]);
    expect(union.unknownSensitive, isTrue);
  });

  test('a union and recursion in event data are mapped as data', () {
    final fixture = IrFixture(
      _spec(
        r'''
                oneOf:
                  - properties:
                      event: {const: tree}
                      data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Node'}}
                  - properties:
                      event: {const: pet}
                      data: {type: string, contentMediaType: application/json, contentSchema: {oneOf: [{$ref: '#/components/schemas/Cat'}, {type: integer}]}}''',
        schemas:
            '{Node: {type: object, properties: {children: {type: array, '
            r"items: {$ref: '#/components/schemas/Node'}}}}, "
            'Cat: {type: object, properties: {name: {type: string}}}}',
      ),
    );
    final ir = fixture.build();
    expect(_variants(ir, _union(ir)), [
      'tree WatchEventTree Node',
      'pet WatchEventPet WatchEventPetData',
    ]);
  });
}
