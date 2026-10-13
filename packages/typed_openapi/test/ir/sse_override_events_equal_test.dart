import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose `feed` streams objects with a string property `a`.
const _spec = '''
openapi: 3.1.0
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
              schema: {type: object, properties: {a: {type: string}}}
''';

void main() {
  test('events that write the schema the spec has are not TOA807', () {
    final fixture = IrFixture(
      _spec,
      overrides: '''
operations:
  feed: {sse: {events: {a: {type: string}, eof: null}}}
''',
    );
    final feed = fixture.build().groups.single.operations.single;
    // Without the override the schema is the JSON of the data (a model).
    expect(
      [for (final v in feed.events!.union!.variants) v.event],
      [
        'a',
        'eof',
      ],
    );
    expect(
      fixture.diagnostics.all.where(
        (d) => d.code == DiagnosticCode.overrideUnchanged,
      ),
      isEmpty,
    );
  });
}
