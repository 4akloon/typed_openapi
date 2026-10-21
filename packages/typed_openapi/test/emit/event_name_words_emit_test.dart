import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

const _spec = '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
                oneOf:
                  - properties:
                      event: {const: USER_INBOX_UNREAD_COUNT_UPDATED}
                      data: {type: string, contentMediaType: application/json, contentSchema: {type: object, properties: {count: {type: integer}}}}
''';

void main() {
  test('a SCREAMING_SNAKE event names its class and data file in words', () {
    final fixture = NormalizedFixture(_spec);
    final ir = IrBuilder(
      fixture.diagnostics,
    ).build(fixture.spec, fixture.client);
    final files = const ApiLibrary().files(ir, client: 'api');
    expect(
      files.keys,
      contains(
        'models/watch_event_user_inbox_unread_count_updated_data.dart',
      ),
    );
    expect(
      files['api/t_api.dart'],
      contains('class WatchEventUserInboxUnreadCountUpdated '),
    );
    expect(
      files['api/t_api.dart'],
      contains('USER_INBOX_UNREAD_COUNT_UPDATED'),
    );
  });
}
