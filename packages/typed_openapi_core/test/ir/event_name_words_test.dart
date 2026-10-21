import 'package:test/test.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/names.dart';

import '../helpers/ir_fixture.dart';

const _event = 'USER_INBOX_UNREAD_COUNT_UPDATED';

const _object = '{type: object, properties: {count: {type: integer}}}';

String _spec(String stream) =>
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
$stream
''';

/// The variant names and the data type names of the only union of [ir].
List<String> _names(ClientIr ir) {
  final union = ir.groups.single.operations.single.events!.union!;
  return [
    for (final v in union.variants) ...[
      v.name,
      if (v.data != null) v.data!.code(ir.nameOf),
    ],
  ];
}

void main() {
  group('eventPascal', () {
    const names = DartNames();
    const cases = {
      _event: 'UserInboxUnreadCountUpdated',
      'user.created': 'UserCreated',
      'user-created': 'UserCreated',
      'userCreated': 'UserCreated',
      'HTTP_ERROR': 'HttpError',
      'HTTP': 'Http',
      'message': 'Message',
      'order2_shipped': 'Order2Shipped',
      'UserDTO_ready': 'UserDTOReady',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('$key is $value', () => expect(names.eventPascal(key), value));
    }

    test('a name with no letter or digit is null', () {
      expect(names.eventPascal('--'), isNull);
    });

    test('pascal is unchanged', () {
      expect(names.pascal(_event), 'USERINBOXUNREADCOUNTUPDATED');
    });
  });

  test('an sse.events override splits the event name into words', () {
    final fixture = IrFixture(
      _spec('''
              schema: {type: string}'''),
      overrides:
          '''
operations:
  watch: {sse: {events: {$_event: $_object}}}
''',
    );
    expect(_names(fixture.build()), [
      'WatchEventUserInboxUnreadCountUpdated',
      'WatchEventUserInboxUnreadCountUpdatedData',
    ]);
  });

  test('an itemSchema oneOf splits the event name into words', () {
    final fixture = IrFixture(
      _spec(
        '''
              itemSchema:
                oneOf:
                  - properties:
                      event: {const: $_event}
                      data: {type: string, contentMediaType: application/json, contentSchema: $_object}''',
      ),
    );
    expect(_names(fixture.build()), [
      'WatchEventUserInboxUnreadCountUpdated',
      'WatchEventUserInboxUnreadCountUpdatedData',
    ]);
  });
}
