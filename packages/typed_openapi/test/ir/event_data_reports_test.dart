import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

const _stream =
    '#/paths/~1feed/get/responses/200/content/text~1event-stream/itemSchema';

/// An OpenAPI 3.2 spec whose `GET /feed` (`watch`) streams events of the
/// `itemSchema` [item] (YAML under `itemSchema:`), with [schemas].
String _spec(String item, {String schemas = '{}'}) =>
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
components:
  schemas: $schemas
''';

/// The events of the method `watch` of [fixture].
EventStreamIr _events(IrFixture fixture) => fixture
    .build()
    .groups
    .single
    .operations
    .firstWhere((o) => o.name == 'watch')
    .events!;

/// The TOA101 errors of [fixture], reported when the spec was read.
List<Object> _resolverErrors(IrFixture fixture) => [
  for (final d in fixture.diagnostics.all)
    if (d.code == DiagnosticCode.unresolvedRef) d,
];

/// The pointers of the TOA666 reports of [fixture].
List<String?> _unread(IrFixture fixture) => [
  for (final d in fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread))
    d.pointer?.value,
];

void main() {
  group('TOA666', () {
    test('is not reported for text data with a text contentMediaType', () {
      final fixture = IrFixture(
        _spec(
          '                properties: {data: {type: string, '
          'contentMediaType: text/plain}}',
        ),
      );
      final events = _events(fixture);
      expect(events.data, isNull);
      expect(events.union, isNull);
      expect(_unread(fixture), isEmpty);
    });

    test('is reported for JSON data without a contentSchema', () {
      final fixture = IrFixture(
        _spec(
          '                properties: {data: {type: string, '
          'contentMediaType: application/json}}',
        ),
      );
      _events(fixture);
      expect(_unread(fixture), [_stream]);
    });

    test('is not reported for the data of an allOf wrapper', () {
      final fixture = IrFixture(
        _spec('''
                allOf:
                  - properties: {data: {type: string}}'''),
      );
      expect(_events(fixture).data, isNull);
      expect(_unread(fixture), isEmpty);
    });

    test('reads JSON data through an allOf wrapper', () {
      final fixture = IrFixture(
        _spec(
          r'''
                allOf:
                  - properties: {event: {type: string}}
                  - properties:
                      data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Tick'}}''',
          schemas: '{Tick: {type: object, properties: {n: {type: integer}}}}',
        ),
      );
      final events = _events(fixture);
      expect(events.data?.code(fixture.build().nameOf), 'Tick');
      expect(_unread(fixture), isEmpty);
    });

    test('adds nothing to the error of an itemSchema that is missing', () {
      final fixture = IrFixture(
        _spec(r"                $ref: '#/components/schemas/Missing'"),
      );
      _events(fixture);
      expect(_resolverErrors(fixture), hasLength(1));
      expect(_unread(fixture), isEmpty);
    });

    test('adds nothing to the error of a data that is missing', () {
      final fixture = IrFixture(
        _spec(
          r"                properties: {data: {$ref: '#/components/schemas/Gone'}}",
        ),
      );
      _events(fixture);
      expect(_resolverErrors(fixture), hasLength(1));
      expect(_unread(fixture), isEmpty);
    });

    test('names the branch of a union that has no constant event', () {
      final fixture = IrFixture(
        _spec(
          '''
                oneOf:
                  - properties: {event: {const: a}, data: {type: string}}
                  - properties: {event: {type: string}, data: {type: string}}''',
        ),
      );
      final events = _events(fixture);
      expect(events.union, isNull);
      expect(_unread(fixture), ['$_stream/oneOf/1']);
      final report = fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread);
      expect(report.single.message, contains('branch'));
      expect(report.single.message, contains('"event"'));
    });

    test('names the allOf branch of a union and says how to fix it', () {
      final fixture = IrFixture(
        _spec(
          r'''
                anyOf:
                  - properties: {event: {const: a}}
                  - allOf:
                      - $ref: '#/components/schemas/Base'
                      - properties: {event: {const: b}}''',
          schemas: '{Base: {properties: {data: {type: string}}}}',
        ),
      );
      _events(fixture);
      final report = fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread);
      expect(report.single.pointer?.value, '$_stream/anyOf/1');
      expect(report.single.fix, contains('allOf'));
    });

    test('is not reported again at the itemSchema for a named branch', () {
      final fixture = IrFixture(
        _spec('''
                oneOf:
                  - properties: {event: {type: string}}'''),
      );
      _events(fixture);
      expect(_unread(fixture), ['$_stream/oneOf/0']);
    });
  });

  group('event names', () {
    test('TOA668 and the lossy name TOA559 point at the branch', () {
      final fixture = IrFixture(
        _spec('''
                oneOf:
                  - properties: {event: {const: ok}}
                  - properties: {event: {const: "*/"}}
                  - properties: {event: {const: "café"}}'''),
      );
      fixture.build();
      expect(
        fixture
            .reportedOf(DiagnosticCode.eventNameUnrepresentable)
            .single
            .pointer
            ?.value,
        '$_stream/oneOf/1',
      );
      expect(
        fixture.reportedOf(DiagnosticCode.nameLossy).single.pointer?.value,
        '$_stream/oneOf/2',
      );
    });

    test('an empty one is reported and left out', () {
      final fixture = IrFixture(
        _spec('''
                oneOf:
                  - properties: {event: {const: ""}}
                  - properties: {event: {const: ok}}'''),
      );
      final union = _events(fixture).union!;
      expect([for (final v in union.variants) v.event], ['ok']);
      final report = fixture.reportedOf(DiagnosticCode.eventNameUnreachable);
      expect(report.single.pointer?.value, '$_stream/oneOf/0');
      expect(report.single.message, contains('"message"'));
    });

    test('one with a line break is reported and left out', () {
      final fixture = IrFixture(
        _spec(r'''
                oneOf:
                  - properties: {event: {const: "a\nb"}}
                  - properties: {event: {const: "c\rd"}}
                  - properties: {event: {const: ok}}'''),
      );
      final union = _events(fixture).union!;
      expect([for (final v in union.variants) v.event], ['ok']);
      expect(
        [
          for (final d in fixture.reportedOf(
            DiagnosticCode.eventNameUnreachable,
          ))
            d.pointer?.value,
        ],
        ['$_stream/oneOf/0', '$_stream/oneOf/1'],
      );
    });

    test('that leave no branch make the data text', () {
      final fixture = IrFixture(
        _spec('''
                oneOf:
                  - properties: {event: {const: ""}, data: {type: string}}'''),
      );
      final events = _events(fixture);
      expect(events.union, isNull);
      expect(
        fixture.reportedOf(DiagnosticCode.eventNameUnreachable),
        hasLength(1),
      );
      expect(_unread(fixture), isEmpty);
    });

    test('a name with a line break in an events override is left out', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: watch
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
''',
        overrides: r'''
operations:
  watch:
    sse:
      events:
        "a\nb": {type: string}
        ok: {type: string}
''',
      );
      final union = _events(fixture).union!;
      expect([for (final v in union.variants) v.event], ['ok']);
      expect(
        fixture
            .reportedOf(DiagnosticCode.eventNameUnreachable)
            .single
            .pointer
            ?.value,
        JsonPointer.root
            .child('operations')
            .child('watch')
            .child('sse')
            .child('events')
            .child('a\nb')
            .value,
      );
    });
  });
}
