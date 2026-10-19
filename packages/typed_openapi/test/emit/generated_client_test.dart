@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';
import '../helpers/temp_dir.dart';

/// Runs `dart` with [arguments] in [directory].
ProcessResult dart(List<String> arguments, String directory) => Process.runSync(
  Platform.resolvedExecutable,
  arguments,
  workingDirectory: directory,
);

void main() {
  group('a package of generated clients', () {
    late String package;

    setUpAll(() {
      final temp = TempDir();
      package = temp.path;
      final runtime = p.normalize(
        p.absolute(p.join('..', 'typed_openapi_client')),
      );
      temp
        ..write('pubspec.yaml', '''
name: fixture
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  dio: ^5.11.1
  typed_openapi_client:
    path: ${runtime.replaceAll(r'\', '/')}
dev_dependencies:
  lints: ^6.1.0
''')
        // package:lints/recommended and the rules flutter_lints adds.
        ..write('analysis_options.yaml', '''
include: package:lints/recommended.yaml
linter:
  rules:
    - avoid_print
    - avoid_unnecessary_containers
    - avoid_web_libraries_in_flutter
    - no_logic_in_create_state
    - prefer_const_constructors_in_immutables
    - sized_box_for_whitespace
    - sort_child_properties_last
    - use_build_context_synchronously
    - use_full_hex_values_for_flutter_colors
    - use_key_in_widget_constructors
''')
        ..write(
          'bin/calls.dart',
          File(
            p.join('test', 'emit', 'programs', 'calls.dart.txt'),
          ).readAsStringSync(),
        );
      for (final program in [
        'fake_dio',
        'wire_calls',
        'stream_calls',
        'hostile_events',
        'union_calls',
      ]) {
        temp.write(
          'bin/$program.dart',
          File(
            p.join('test', 'emit', 'programs', '$program.dart.txt'),
          ).readAsStringSync(),
        );
      }
      for (final fixture in [
        'petstore',
        'hostile_operations',
        'pets',
        'everything',
        'hostile',
        'secrets',
        'status_bodies',
        'hierarchy',
        'wire',
        'chat',
        'events_hostile',
        'event_bodies',
        'event_ranges',
        'discriminator_scalars',
        'optional_constant',
      ]) {
        for (final mode in UnionMode.values) {
          final files = emitClient(
            '$fixture.yaml',
            generation: GenerationConfig(union: mode),
          );
          for (final MapEntry(:key, :value) in files.entries) {
            temp.write(p.join('lib', '${fixture}_${mode.name}', key), value);
          }
        }
      }
      for (final mode in UnionMode.values) {
        final files = emitClient(
          'chat.yaml',
          generation: GenerationConfig(union: mode),
          overrides: 'chat.overrides.yaml',
        );
        for (final MapEntry(:key, :value) in files.entries) {
          temp.write(p.join('lib', 'chat_override_${mode.name}', key), value);
        }
      }
      final get = dart(['pub', 'get', '--offline'], package);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    });

    test('passes dart analyze with the recommended lints (R13.2)', () {
      final result = dart(['analyze', '--fatal-infos'], package);
      expect(result.exitCode, 0, reason: '${result.stdout}');
    });

    test('sends requests and decodes every outcome (R10, R11)', () {
      final result = dart(['run', 'bin/calls.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _calls);
    });

    test('streams events, reconnects and cancels (R12)', () {
      final result = dart(['run', 'bin/stream_calls.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _streams);
    });

    test('dispatches hostile event names by their exact name (R12.2)', () {
      final result = dart(['run', 'bin/hostile_events.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _hostileEvents);
    });

    test('decodes a discriminated union of scalars and optional constants', () {
      final result = dart(['run', 'bin/union_calls.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _unions);
    });

    test('puts every value on the wire as the spec says (R10)', () {
      final result = dart(['run', 'bin/wire_calls.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _wire);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// What `bin/hostile_events.dart` prints.
const _hostileEvents = r'''
Delta -> FeedEventDelta(d-Delta)
delta -> FeedEventDelta2(d-delta)
- -> FeedEventEvent1()
*/ -> FeedEventEvent2(d-*/)
a b -> FeedEventAB(d-a b)
class -> FeedEventClass(d-class)
unknown -> FeedEventUnknown2(d-unknown)
secret -> FeedEventSecret(<redacted>)
nothing -> FeedEventUnknown(nothing, <redacted>)
$cost -> FeedEventCost(d-$cost)
message -> FeedEventUnknown(message, <redacted>)
message -> FeedEventUnknown(message, <redacted>)
end
''';

/// What `bin/stream_calls.dart` prints.
const _streams = '''
success 200
  event message # Delta(part: Hel, sessionToken: <redacted>)
  decode error /part
  event delta #2 Delta(part: lo, sessionToken: <redacted>)
  end closed
POST https://chat.example.com/chat accept text/event-stream
JSON method accept application/json
  reply hello
JSON method with an Accept of the call text/plain
error 400 Problem(code: empty)
success 200
  event message # Delta(part: a, sessionToken: <redacted>)
  end closed
requests 1
success 200
  event message #7 Thread(id: t1, replies: [])
  reconnecting 1 after 1500ms
  event message #7 Thread(id: t2, replies: null)
  reconnecting 1 after 1500ms
  end closed
waits [1500, 1500]
last event ids [null, 7, 7]
path /threads/a%2Fb/events
success 200
  event message # Thread(id: t1, replies: null)
  reconnecting 1 after 1000ms
  reconnecting 2 after 1500ms
  reconnecting 3 after 1500ms
  end connectionError
waits [1000, 1500, 1500]
  event message # Thread(id: t1, replies: null)
  reconnecting 1 after 1000ms
  end cancel
requests 1
  event message # Thread(id: t1, replies: null)
  end cancel
  delta Hi
  usage 3
  note plain text
  FollowChatEventUnknown(ping, <redacted>)
  decode error /tokens
  done
  end closed
overridden
  FollowChatEventDone()
  end closed
  TailLogEventLine(one)
  TailLogEventStats(Usage(tokens: 2))
  TailLogEventEof()
  reconnecting 1 after 1000ms
  end UndocumentedStatus(204)
  requests 2
POST /chat accept text/event-stream
  end closed
success 200
  event message # line 1
line 2
  end closed
failure UndocumentedStatus(503)
''';

/// What `bin/union_calls.dart` prints.
const _unions = '''
value 1.5 -> ValueNum 1.5
value 3 -> ValueInt 3
value "x" -> ValueString "x"
value "red" -> ValueString "red"
value true -> decode at ""
value null -> decode at ""
value {"kind":"cat","lives":9} -> ValueCat {"kind":"cat","lives":9}
value {"kind":"dog"} -> ValueUnknown {"kind":"dog"}
defaulted {"kind":"other","barks":1} -> DefaultedDog {"kind":"other","barks":1}
defaulted {"barks":2} -> decode at "/kind"
defaulted "text" -> DefaultedString "text"
bare {"kind":"zzz","size":1} -> BarePlain {"size":1,"kind":"zzz"}
bare {"size":2} -> BarePlain {"size":2,"kind":"plain"}
bare false -> BareBool false
facet -> FacetValueFacet {"field":"f"}
value facet {"field":"f"} -> {"field":"f"}
value facet {"field":"f","type":"value"} -> {"field":"f","type":"value"}
value facet {"field":"f","version":2} -> {"field":"f","version":2}
value facet {"field":"f","type":"value","version":2} -> {"field":"f","type":"value","version":2}
made in code {"field":"f","type":"value","version":2}
same getters true
equal false
equal to its own decoding true
''';

/// What `bin/wire_calls.dart` prints.
const _wire = r'''
success 204 null
https://wire.example.com/helpers?jsonEncode=%22a%5C%22b%22&base64Encode=AQID
multipart [true, true, true]
success 204 null
avatar: image/png | scan: application/octet-stream | meta: application/json; charset=utf-8 | history: application/xml; charset=utf-8 | rows: text/csv; charset=utf-8 | note: text/plain; charset=utf-8 | broken: text/plain; charset=utf-8
success 204 null
avatar: image/png | scan: image/webp | meta: application/json; charset=utf-8 | history: application/xml; charset=utf-8 | rows: text/csv; charset=utf-8 | note: text/plain; charset=utf-8 | broken: text/plain; charset=utf-8
POST /strings application/json <"hello \"q\"">
PUT /strings application/json <"red">
PATCH /strings application/json <"x\"y">
PATCH /strings application/json <null>
POST /nullable application/json <"n">
POST /nullable application/json <null>
POST /optional application/json <"o">
POST /optional null <>
PUT /optional text/plain <plain "t">
PUT /optional null <>
PATCH /optional null <>
success 200 Report r1
error 404 NotFound bytes 1,2,3,250
error 409 Conflict text "taken "x""
error 409 Conflict text ""
error 422 Unprocessable bytes 60,101,47,62
success 200 Report r2
error 400 text "bad "x""
error 500 text "boom"
error 400 text ""
success 200 Report r3
error 400 Report e1
''';

/// What `bin/calls.dart` prints: each call's request and result.
const _calls = '''
server https://us.pets.example.com/v1 http://localhost:8080
success 200 Pets Rex
GET https://pets.example.com/v1/pets?limit=5&tags=a%20b%7Cc&status=available,sold&filter%5Bkind%5D=dog&next=/a//b?c&where=%7B%22age%22%3A3%7D [listPets; bearer]
headers t-1 session=s%201
error 500 Problem down
success 200 Ok Rex
success 201 Created job-1
success 204 NoContent
error 404 NotFound gone
error 422 ClientError bad
error 503 ServiceUnavailable
undocumented 302
decode /id an integer
body {"id":1,"name":"Rex","status":"available"}
CreatePetErrorNotFound(Problem(code: gone, password: <redacted>))
CreatePetResponseCreated(Job(id: job-2))
CreatePetResponseNoContent()
CreatePetErrorServiceUnavailable()
success 200 Pet 7 Tom null
GET https://pets.example.com/v1/pets/7 [getPet; bearer]
success 204 null
DELETE https://pets.example.com/v1/pets/7 [deletePet; ] reason=old
success 200 bytes 3
received 3
GET https://pets.example.com/v1/pets/.7/photo [getPhoto; bearer]
error 404 Problem nophoto
success 200 text hello
GET https://pets.example.com/v1/pets/;petId=1;petId=2/note [getNote; bearer]
error 404 Problem nonote
success 204 null
application/octet-stream png
success 204 null
image/gif gif
success 204 null
multipart [true, true, true, true, true]
success 200 Order 3 pending
POST https://pets.example.com/v1/store/orders [placeOrder; apiKey|] application/x-www-form-urlencoded petId=1&tags=a,b&meta%5Bk%5D=v
success 200 json {"any":true}
text/plain note
error 400 json {"ok":false}
success 200 null
extra 1
cancelled
transport
decode /data/id an integer
''';
