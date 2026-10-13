import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose `mixed` has a stream success that is a shared response
/// (200) and one written in the operation (201), both of text, or, when
/// [shared] says so, of `Delta`.
String _spec({required String shared}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /mixed:
    get:
      operationId: mixed
      responses:
        "200": {\$ref: '#/components/responses/Events'}
        "201":
          description: made
          content:
            text/event-stream: {schema: {type: string}}
components:
  responses:
    Events:
      description: shared
      content:
        text/event-stream: {schema: $shared}
  schemas:
    Delta: {type: object, properties: {part: {type: string}}}
''';

/// The methods of [fixture] by name.
Map<String, OperationIr> _methods(IrFixture fixture) => {
  for (final group in fixture.build().groups)
    for (final o in group.operations) o.name: o,
};

void main() {
  group('sse.events on a shared and a written stream success', () {
    test('changes the written one and names the shared one (TOA669)', () {
      final fixture = IrFixture(
        _spec(shared: '{type: string}'),
        overrides: 'operations:\n  mixed: {sse: {events: {a: Delta}}}\n',
      );
      _methods(fixture);
      final report = fixture.reportedOf(DiagnosticCode.sseOverrideNotApplied);
      expect(report.single.pointer?.value, '#/operations/mixed/sse');
      expect(report.single.message, contains('shared response of status 200'));
      expect(report.single.message, contains('"events"'));
    });

    test('differs from the shared one, so TOA654 says it was not changed', () {
      final fixture = IrFixture(
        _spec(shared: '{type: string}'),
        overrides: 'operations:\n  mixed: {sse: {events: {a: Delta}}}\n',
      );
      expect(_methods(fixture), isEmpty);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report.single.message, contains('shared response of status 200'));
      expect(report.single.message, contains('not overridden'));
      expect(report.single.fix, contains('component'));
      expect(report.single.fix, contains('write the response'));
    });

    test('is a stream of the data when the shared one has that type', () {
      final fixture = IrFixture(
        _spec(shared: r"{$ref: '#/components/schemas/Delta'}"),
        overrides: 'operations:\n  mixed: {sse: {data: Delta}}\n',
      );
      final mixed = _methods(fixture)['mixed']!;
      expect(mixed.events!.data?.code(fixture.build().nameOf), 'Delta');
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated),
        isEmpty,
      );
      final report = fixture.reportedOf(DiagnosticCode.sseOverrideNotApplied);
      expect(report.single.message, contains('"data"'));
      expect(report.single.message, contains('status 200'));
    });

    test('has no TOA654 note without an override', () {
      final fixture = IrFixture(
        _spec(shared: '{type: integer}'),
      );
      expect(_methods(fixture), isEmpty);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report.single.message, isNot(contains('shared')));
      expect(
        fixture.reportedOf(DiagnosticCode.sseOverrideNotApplied),
        isEmpty,
      );
    });
  });
}
