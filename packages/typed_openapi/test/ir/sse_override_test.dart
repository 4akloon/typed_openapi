import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec with a POST `chat` that offers JSON and events, a GET `feed` of
/// text events with an `itemSchema`, a GET `plain` without events and a
/// GET `shared` whose stream response is a `$ref`.
const _spec = r'''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /chat:
    post:
      operationId: chat
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {$ref: '#/components/schemas/Reply'}}
            text/event-stream: {schema: {type: string}}
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: string}}}
  /plain:
    get:
      operationId: plain
      responses:
        "204": {description: none}
  /shared:
    get:
      operationId: shared
      responses:
        "200": {$ref: '#/components/responses/Events'}
components:
  responses:
    Events:
      description: shared
      content:
        text/event-stream: {schema: {type: string}}
  schemas:
    Reply: {type: object, properties: {text: {type: string}}}
    Delta: {type: object, properties: {part: {type: string}}}
''';

/// The methods of the client built with the overrides [overrides].
(Map<String, OperationIr>, ClientIr, IrFixture) _build(String overrides) {
  final fixture = IrFixture(_spec, overrides: overrides);
  final ir = fixture.build();
  return (
    {
      for (final group in ir.groups)
        for (final o in group.operations) o.name: o,
    },
    ir,
    fixture,
  );
}

void main() {
  test('data wins over itemSchema and schema', () {
    final (methods, ir, fixture) = _build('''
operations:
  feed: {sse: {data: Delta}}
  chat: {sse: {data: {type: object, properties: {n: {type: integer}}}}}
''');
    expect(methods['feed']!.events!.data?.code(ir.nameOf), 'Delta');
    expect(
      methods['chatStream']!.events!.data?.code(ir.nameOf),
      'ChatStreamEvent',
    );
    expect(fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread), isEmpty);
  });

  test('events are a union in the order of the override', () {
    final (methods, ir, _) = _build('''
operations:
  feed: {sse: {events: {delta: Delta, done: null, note: {type: string}}}}
''');
    final union = methods['feed']!.events!.union!;
    expect(
      [
        for (final v in union.variants)
          '${v.event} ${v.name} '
              '${v.hasData ? v.data?.code(ir.nameOf) ?? 'String' : '-'}',
      ],
      [
        'delta FeedEventDelta Delta',
        'done FeedEventDone -',
        'note FeedEventNote String',
      ],
    );
    expect(union.keepUnknown, isTrue);
    expect(union.unknownName, 'FeedEventUnknown');
  });

  test('unknown: ignore drops the unknown variant', () {
    final (methods, _, _) = _build('''
operations:
  feed: {sse: {events: {a: null}, unknown: ignore}}
''');
    final union = methods['feed']!.events!.union!;
    expect(union.keepUnknown, isFalse);
    expect(union.unknownName, '');
  });

  test('reconnect turns a POST on and a GET off, without TOA665', () {
    final (methods, _, fixture) = _build('''
operations:
  chat: {sse: {reconnect: true}}
  feed: {sse: {reconnect: false}}
''');
    expect(methods['chatStream']!.events!.reconnection, StreamReconnection.on);
    expect(methods['feed']!.events!.reconnection, StreamReconnection.off);
    expect(fixture.reportedOf(DiagnosticCode.eventStreamReconnectOff), isEmpty);
  });

  test('method only keeps the stream under the operation name', () {
    final (methods, _, fixture) = _build('''
operations:
  chat: {sse: {method: only}}
''');
    expect(methods.keys, isNot(contains('chatStream')));
    expect(methods['chat']!.events, isNotNull);
    expect(fixture.reportedOf(DiagnosticCode.eventStreamMethodAdded), isEmpty);
  });

  test('method none keeps the JSON method, or leaves out a stream', () {
    final (methods, _, _) = _build('''
operations:
  chat: {sse: {method: none}}
  feed: {sse: {method: none}}
''');
    expect(methods['chat']!.events, isNull);
    expect(methods.keys, isNot(contains('chatStream')));
    expect(methods.keys, isNot(contains('feed')));
  });

  test('sse finds no event stream written in the operation (TOA669)', () {
    final (_, _, fixture) = _build('''
operations:
  plain: {sse: {reconnect: true}}
  shared: {sse: {data: Delta}}
''');
    expect(
      [
        for (final d in fixture.diagnostics.all)
          if (d.code == DiagnosticCode.sseOverrideNotApplied) d.pointer?.value,
      ],
      ['#/operations/plain/sse', '#/operations/shared/sse'],
    );
  });
}
