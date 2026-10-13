import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// An OpenAPI 3.2 spec whose `watch` streams events of the `itemSchema`
/// [item] (YAML under `itemSchema:`), with [schemas].
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

const _itemSchema =
    '#/paths/~1feed/get/responses/200/content/text~1event-stream/itemSchema';

/// The events of `watch`.
EventStreamIr _events(IrFixture fixture) => fixture
    .build()
    .groups
    .single
    .operations
    .firstWhere((o) => o.name == 'watch')
    .events!;

void main() {
  test('a referenced branch fixes the event name through its target', () {
    final fixture = IrFixture(
      _spec(
        r'''
                oneOf:
                  - $ref: '#/components/schemas/Done'
                  - properties: {event: {const: note}, data: {type: string}}''',
        schemas: '{Done: {properties: {event: {const: done}}}}',
      ),
    );
    final union = _events(fixture).union!;
    expect([for (final v in union.variants) v.event], ['done', 'note']);
    expect(
      fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread),
      isEmpty,
    );
  });

  test('a nested oneOf branch makes the data text, at the branch', () {
    final fixture = IrFixture(
      _spec('''
                oneOf:
                  - properties: {event: {const: a}}
                  - oneOf:
                      - properties: {event: {const: b}}
                      - properties: {event: {const: c}}'''),
    );
    final events = _events(fixture);
    expect(events.union, isNull);
    expect(events.data, isNull);
    expect(
      [
        for (final d in fixture.reportedOf(
          DiagnosticCode.eventItemSchemaUnread,
        ))
          d.pointer?.value,
      ],
      ['$_itemSchema/oneOf/1'],
    );
  });

  test('a discriminator beside the branches does not stop the union', () {
    final fixture = IrFixture(
      _spec('''
                discriminator: {propertyName: event}
                oneOf:
                  - properties: {event: {const: a}, data: {type: string}}
                  - properties: {event: {const: b}}'''),
    );
    final union = _events(fixture).union!;
    expect([for (final v in union.variants) v.event], ['a', 'b']);
    expect(
      fixture.reportedOf(DiagnosticCode.eventItemSchemaUnread),
      isEmpty,
    );
  });

  test('an allOf branch makes the data text, at the branch', () {
    final fixture = IrFixture(
      _spec('''
                oneOf:
                  - allOf:
                      - properties: {event: {const: a}}'''),
    );
    expect(_events(fixture).union, isNull);
    expect(
      [
        for (final d in fixture.reportedOf(
          DiagnosticCode.eventItemSchemaUnread,
        ))
          d.pointer?.value,
      ],
      ['$_itemSchema/oneOf/0'],
    );
  });
}
