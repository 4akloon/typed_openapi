import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose `multi` has two event-stream successes (200, and 201 with a
/// charset), `shared` and `other` that share one stream response, `plain`
/// without a stream and a `feed` of text events.
const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /multi:
    get:
      operationId: multi
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            text/event-stream; charset=utf-8: {schema: {type: string}}
  /shared:
    get:
      operationId: shared
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /other:
    get:
      operationId: other
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /plain:
    get:
      operationId: plain
      responses:
        "204": {description: none}
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
components:
  responses:
    Events:
      description: shared
      content:
        text/event-stream: {schema: {type: string}}
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''';

/// The IR of the spec with the overrides [overrides], its methods by name,
/// and the fixture.
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

/// The TOA669 reports of [fixture] as pointer and message.
List<(String?, String)> _notApplied(IrFixture fixture) => [
  for (final d in fixture.diagnostics.all)
    if (d.code == DiagnosticCode.sseOverrideNotApplied)
      (d.pointer?.value, d.message),
];

/// A 3.2 spec whose `shared` and `other` share a stream response that names
/// its events by `itemSchema`, and whose `feed` has its own text stream.
const _spec32 = r'''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /shared:
    get:
      operationId: shared
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /other:
    get:
      operationId: other
      responses:
        "200": {$ref: '#/components/responses/Events'}
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
components:
  responses:
    Events:
      description: shared
      content:
        text/event-stream:
          itemSchema:
            oneOf:
              - properties:
                  event: {const: tick}
                  data: {type: string}
              - properties:
                  event: {const: tock}
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''';

/// The methods of [_spec32] with the overrides [overrides].
(Map<String, OperationIr>, IrFixture) _build32(String overrides) {
  final fixture = IrFixture(_spec32, overrides: overrides);
  return (
    {
      for (final group in fixture.build().groups)
        for (final o in group.operations) o.name: o,
    },
    fixture,
  );
}

void main() {
  group('events with several event-stream successes', () {
    test('give one stream method with one union', () {
      final (methods, _, fixture) = _build('''
operations:
  multi: {sse: {events: {a: Delta, b: null}}}
''');
      final union = methods['multi']!.events!.union!;
      expect(
        [for (final v in union.variants) v.event],
        ['a', 'b'],
      );
      expect(methods.keys.where((n) => n.startsWith('multi')), ['multi']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });

    test('and data give the same stream', () {
      final (methods, _, fixture) = _build('''
operations:
  multi: {sse: {data: Delta}}
''');
      expect(methods['multi']!.events!.data, isNotNull);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });

    test('replace the itemSchema of each success in OpenAPI 3.2', () {
      final fixture = IrFixture(
        '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /multi:
    get:
      operationId: multi
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: string}}}
        "201":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: integer}}}
components:
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''',
        overrides: '''
operations:
  multi: {sse: {events: {a: Delta}}}
''',
      );
      final methods = [
        for (final group in fixture.build().groups)
          for (final o in group.operations) o.name,
      ];
      expect(methods, ['multi']);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
    });
  });

  group('what a shared response lets the override do', () {
    test('reconnect applies and TOA669 does not say it changes nothing', () {
      final (methods, fixture) = _build32('''
operations:
  shared: {sse: {reconnect: true}}
''');
      expect(methods['shared']!.events!.reconnection, StreamReconnection.on);
      expect(_notApplied(fixture), isEmpty);
    });

    test('method none leaves a stream-only operation out without TOA669', () {
      final (methods, fixture) = _build32('''
operations:
  shared: {sse: {method: none}}
''');
      expect(methods.keys, isNot(contains('shared')));
      expect(methods.keys, contains('other'));
      expect(_notApplied(fixture), isEmpty);
    });

    test('unknown ignore applies to this operation only', () {
      final (methods, fixture) = _build32('''
operations:
  shared: {sse: {unknown: ignore}}
''');
      expect(methods['shared']!.events!.union!.keepUnknown, isFalse);
      expect(methods['other']!.events!.union!.keepUnknown, isTrue);
      expect(_notApplied(fixture), isEmpty);
    });

    test('events with no data build no union on it and are TOA669', () {
      final (methods, fixture) = _build32('''
operations:
  shared: {sse: {events: {x: null, y: null}}}
''');
      final union = methods['shared']!.events!.union!;
      expect([for (final v in union.variants) v.event], ['tick', 'tock']);
      expect(_notApplied(fixture), hasLength(1));
      expect(_notApplied(fixture).single.$1, '#/operations/shared/sse');
      expect(_notApplied(fixture).single.$2, contains('"events"'));
    });

    test('TOA669 names the data and not the fields that apply', () {
      final (methods, fixture) = _build32('''
operations:
  shared: {sse: {data: Delta, reconnect: true}}
''');
      expect(methods['shared']!.events!.reconnection, StreamReconnection.on);
      final report = _notApplied(fixture).single;
      expect(report.$1, '#/operations/shared/sse');
      expect(report.$2, contains('"data"'));
      expect(report.$2, isNot(contains('reconnect')));
    });
  });

  group('an operation without an event stream', () {
    test('has TOA669 that names the fields that change nothing', () {
      final fixture = IrFixture(
        _spec,
        overrides: '''
operations:
  plain: {sse: {reconnect: true, unknown: ignore}}
''',
      )..build();
      final report = _notApplied(fixture).single;
      expect(report.$1, '#/operations/plain/sse');
      expect(report.$2, contains('"reconnect"'));
      expect(report.$2, contains('"unknown"'));
      expect(report.$2, isNot(contains('"method"')));
    });

    test('has TOA669 that names the data when it is all the override has', () {
      final fixture = IrFixture(
        _spec,
        overrides: '''
operations:
  plain: {sse: {data: Delta}}
''',
      )..build();
      final report = _notApplied(fixture).single;
      expect(report.$2, contains('"data"'));
    });
  });

  group('unknown on a stream without events', () {
    test('is TOA669 at the unknown field, also for text', () {
      final (_, _, fixture) = _build('''
operations:
  feed: {sse: {data: Delta, unknown: ignore}}
''');
      final report = _notApplied(fixture).single;
      expect(report.$1, '#/operations/feed/sse/unknown');
      expect(report.$2, contains('"unknown"'));
    });

    test('is not reported when events give the stream a union', () {
      final (_, _, fixture) = _build('''
operations:
  feed: {sse: {events: {a: null}, unknown: ignore}}
''');
      expect(_notApplied(fixture), isEmpty);
    });
  });

  group('events', () {
    test('named by the YAML merge key are left out with TOA669', () {
      final (methods, _, fixture) = _build('''
operations:
  feed: {sse: {events: {"<<": Delta, ok: null}}}
''');
      final union = methods['feed']!.events!.union!;
      expect([for (final v in union.variants) v.event], ['ok']);
      final report = _notApplied(fixture).single;
      expect(report.$1, '#/operations/feed/sse/events/<<');
    });

    test('that are all named by it leave the stream as it is', () {
      final (methods, _, fixture) = _build('''
operations:
  feed: {sse: {events: {"<<": Delta}}}
''');
      expect(methods['feed']!.events!.union, isNull);
      expect(_notApplied(fixture), hasLength(1));
    });
  });

  group('data equal to the spec', () {
    test('is TOA807 and a different one is not', () {
      final (_, _, same) = _build('''
operations:
  feed: {sse: {data: {type: string}}}
''');
      expect(
        same.diagnostics.all.where(
          (d) => d.code == DiagnosticCode.overrideUnchanged,
        ),
        hasLength(1),
      );
      final (_, _, other) = _build('''
operations:
  feed: {sse: {data: {type: integer}}}
''');
      expect(
        other.diagnostics.all.where(
          (d) => d.code == DiagnosticCode.overrideUnchanged,
        ),
        isEmpty,
      );
    });
  });
}
