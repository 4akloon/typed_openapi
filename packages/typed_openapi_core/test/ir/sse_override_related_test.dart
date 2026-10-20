import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

/// A 3.2 spec whose `feed` has an `itemSchema`, which an `sse.data` replaces
/// with a `schema` (two edits of the spec, one override field).
const _spec = '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema: {properties: {data: {type: string}}}
''';

void main() {
  test('a problem an override introduced names the override field once', () {
    final fixture = IrFixture(
      _spec,
      overrides: '''
operations:
  feed: {sse: {data: {type: strng}}}
''',
    );
    final problems = fixture.diagnostics.all.where(
      (d) => d.code == DiagnosticCode.invalidValue,
    );
    expect(problems, isNotEmpty);
    for (final problem in problems) {
      expect(
        [
          for (final r in problem.related)
            if (r.message == 'Introduced by this override.') r.pointer?.value,
        ],
        ['#/operations/feed/sse'],
      );
    }
  });
}
