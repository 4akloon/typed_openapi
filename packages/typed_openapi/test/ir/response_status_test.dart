import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

/// The spec of one operation whose responses are [responses], each with a
/// JSON body unless it is written out in full.
String specOf(Map<String, String> responses) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: read
      tags: [t]
      responses:
${[for (final MapEntry(:key, :value) in responses.entries) '        $key: $value'].join('\n')}
components:
  schemas:
    Item: {type: object, properties: {id: {type: string}}}
''';

String body(String schema) =>
    '{description: d, content: {application/json: {schema: '
    '{type: object, properties: {$schema: {type: string}}}}}}';

(ClientIr, IrFixture) build(Map<String, String> responses) {
  final fixture = IrFixture(specOf(responses));
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return (ir, fixture);
}

List<String> statuses(ClientIr ir) => [
  for (final r in ir.groups.single.operations.single.responses) r.status,
];

void main() {
  group('a response key that is not an HTTP status', () {
    test('never reaches a name: it is reported and skipped', () {
      final (ir, fixture) = build({
        '''"200'; injected(); '"''': body('a'),
        '"2XX"': body('b'),
      });
      expect(statuses(ir), ['2XX']);
      expect(fixture.codes, [
        (
          DiagnosticCode.responseStatusInvalid,
          "#/paths/~1a/get/responses/200'; injected(); '",
        ),
      ]);
      for (final declaration in ir.declarations) {
        expect(declaration.name, matches(RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$')));
      }
    });

    for (final key in [
      '"20X"',
      '"2X0"',
      '"2000"',
      '"99"',
      '"600"',
      '"000"',
      '"+20"',
      '"Default"',
      '"success"',
      '"2 0"',
      '"٢٠٠"',
    ]) {
      test('$key is reported (TOA657) and its response is skipped', () {
        final (ir, fixture) = build({'"200"': body('a'), key: body('b')});
        expect(statuses(ir), ['200']);
        expect(
          [for (final (code, _) in fixture.codes) code],
          [
            DiagnosticCode.responseStatusInvalid,
          ],
        );
      });
    }

    test('names the key and what is accepted', () {
      final (_, fixture) = build({'"200"': body('a'), '"20X"': body('b')});
      final message = fixture.reported.single.message;
      expect(message, contains('"20X"'));
      expect(message, contains('4XX'));
      expect(message, contains('default'));
    });
  });

  group('a valid response key', () {
    test('is accepted as a code, a range in either case or default', () {
      final (ir, fixture) = build({
        '"201"': body('a'),
        '"4xx"': body('b'),
        '"5XX"': body('c'),
        'default': body('d'),
      });
      expect(statuses(ir), ['201', '4XX', '5XX', 'default']);
      expect(fixture.reported, isEmpty);
    });

    test('written as 2xx and 2XX is a duplicate: the second is reported', () {
      final (ir, fixture) = build({'"2XX"': body('a'), '"2xx"': body('b')});
      expect(statuses(ir), ['2XX']);
      expect(fixture.codes, [
        (DiagnosticCode.responseStatusInvalid, '#/paths/~1a/get/responses/2xx'),
      ]);
    });
  });

  group('a documented 1xx or 3xx response', () {
    for (final key in ['"100"', '"1XX"', '"301"', '"3XX"', '"304"']) {
      test('$key is reported as info (TOA658) and not generated', () {
        final (ir, fixture) = build({'"200"': body('a'), key: body('b')});
        expect(statuses(ir), ['200']);
        expect(fixture.codes, [
          (
            DiagnosticCode.responseStatusNotGenerated,
            '#/paths/~1a/get/responses/${key.replaceAll('"', '')}',
          ),
        ]);
        expect(fixture.reported.single.severity.name, 'info');
      });
    }

    test('does not declare a model for its body', () {
      final (ir, _) = build({
        '"200"': body('a'),
        '"304"': body('b'),
      });
      expect(ir.declarations.map((d) => d.name), ['ReadResponse']);
    });
  });

  test(
    'an operation whose only 2xx key is invalid has no success (TOA653)',
    () {
      final (_, fixture) = build({'"20X"': body('a'), '"404"': body('b')});
      expect(
        [for (final (code, _) in fixture.codes) code],
        [
          DiagnosticCode.responseStatusInvalid,
          DiagnosticCode.successUndocumented,
        ],
      );
    },
  );
}
