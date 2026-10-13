@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:typed_openapi/src/config/generation_config.dart';

import '../helpers/emit_fixture.dart';

void main() {
  final files = emitClient('chat.yaml');
  final chat = files['api/chat_api.dart']!;
  final threads = files['api/threads_api.dart']!;

  test('the chat fixture matches its goldens (R12.1)', () {
    final goldens = p.join('test', 'emit', 'goldens', 'chat');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      for (final MapEntry(:key, :value) in files.entries) {
        File(p.join(goldens, '$key.golden'))
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
    }
    final expected = {
      for (final file in Directory(
        goldens,
      ).listSync(recursive: true).whereType<File>())
        p
            .relative(file.path, from: goldens)
            .replaceAll(r'\', '/')
            .replaceAll(RegExp(r'\.golden$'), ''): file
            .readAsStringSync(),
    };
    expect(files.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in files.entries) {
      expect(value, expected[key], reason: key);
    }
  });

  test('JSON and an event stream give two methods', () {
    expect(chat, contains('Future<Result<Reply, Problem>> chat({'));
    expect(
      chat,
      contains(
        'Future<Result<Stream<SseItem<Delta>>, Problem>> chatStream2({',
      ),
    );
    expect(chat, contains('}) => _sender.openEvents('));
  });

  test('a stream method opens for its 2xx statuses only', () {
    expect(threads, contains('streamStatuses: {200, 204},'));
    expect(threads, contains('(m) => Thread.fromJson(JsonReader.asObject('));
  });

  test('a POST stream does not reconnect, a GET does when asked', () {
    expect(chat, contains('reconnection: .off,'));
    expect(
      chat,
      contains(
        "/// with `SseDisconnected`. It does not reconnect unless the operation's"
        '\n  /// `sse.reconnect` override enables it.',
      ),
    );
    expect(threads, isNot(contains('reconnection:')));
  });

  test('events typed by name are a sealed union with an unknown variant', () {
    expect(
      chat,
      contains(
        'Future<Result<Stream<SseItem<FollowChatEvent>>, Never>> followChat({',
      ),
    );
    expect(chat, contains('    FollowChatEvent.fromEvent,'));
    expect(chat, contains('sealed class FollowChatEvent {'));
    expect(chat, contains("    'done' => const FollowChatEventDone(),"));
    expect(
      chat,
      contains('    _ => FollowChatEventUnknown(message.event, message.data),'),
    );
  });

  test('hostile event names are escaped literals and safe names', () {
    final feed = emitClient('events_hostile.yaml')['api/default_api.dart']!;
    for (final pattern in [
      "    '-' => const FeedEventEvent1(),",
      "    '*/' => FeedEventEvent2(message.data),",
      r"    '\$cost' => FeedEventCost(message.data),",
      "    'a b' => FeedEventAB(message.data),",
      r"    '\u{202e}evil' => FeedEventEvil(message.data),",
      "    'unknown' => FeedEventUnknown2(message.data),",
      "    'delta' => FeedEventDelta2(message.data),",
      '/// The `-` event of [DefaultApi.feed], which has no data.',
      "  String toString() => 'FeedEventSecret(<redacted>)';",
      r"  String toString() => 'FeedEventUnknown($event, <redacted>)';",
    ]) {
      expect(feed, contains(pattern));
    }
    expect(feed, isNot(contains('\u202E')));
  });

  test('a reserved word has a stream method named after its stem', () {
    final feed = emitClient('events_hostile.yaml')['api/default_api.dart']!;
    expect(feed, contains('Future<Result<String, Never>> class_({'));
    expect(
      feed,
      contains('Future<Result<Stream<SseItem<String>>, Never>> classStream({'),
    );
    expect(feed, contains('static const _classStream = OperationInfo('));
    expect(feed, isNot(contains('new_Stream')));
  });

  test('text events are the data as it is', () {
    expect(threads, contains('Stream<SseItem<String>>'));
    expect(threads, contains('(m) => m.data,'));
  });

  test(
    'a body that is not JSON next to events stays the body (bytes, text)',
    () {
      final bodies = emitClient('event_bodies.yaml')['api/bodies_api.dart']!;
      for (final signature in [
        'Future<Result<Uint8List, Never>> download({',
        'Future<Result<Stream<SseItem<String>>, Never>> downloadStream({',
        'Future<Result<Uint8List, Never>> report({CallOptions? call}) =>',
        'Future<Result<Stream<SseItem<Tick>>, Never>> reportStream({',
        'Future<Result<String, Never>> note({CallOptions? call}) =>',
        'Future<Result<Tick, Never>> status({CallOptions? call}) =>',
      ]) {
        expect(bodies, contains(signature));
      }
    },
  );

  test('only the JSON method of a JSON and events operation sends Accept', () {
    expect("accept: 'application/json',".allMatches(chat), hasLength(1));
    final json = chat.indexOf('Future<Result<Reply, Problem>> chat({');
    final accept = chat.indexOf("accept: 'application/json',");
    final stream = chat.indexOf('chatStream2({');
    expect(accept, greaterThan(json));
    expect(accept, lessThan(stream));
    expect(threads, isNot(contains('accept:')));
  });

  test('a 2xx range opens the stream for every success status', () {
    final ranges = emitClient('event_ranges.yaml')['api/ranges_api.dart']!;
    expect(
      ranges,
      contains('streamStatuses: {for (var s = 200; s < 300; s++) s},'),
    );
  });

  test('a code and a range together list the range once', () {
    final ranges = emitClient('event_ranges.yaml')['api/ranges_api.dart']!;
    expect(ranges, isNot(contains('{200, for')));
    expect(
      'streamStatuses: {for (var s = 200; s < 300; s++) s},'.allMatches(ranges),
      hasLength(2),
    );
  });

  group('an operation that reconnects', () {
    const sentence =
        'It reconnects with `Last-Event-ID` unless `call.sse` says no.';
    // The doc comment wraps, so compare its words.
    String words(String code) => code.replaceAll(RegExp(r'\n\s*/// ?'), ' ');

    test('by the config is a GET with reconnection on', () {
      final files = emitClient(
        'chat.yaml',
        generation: const GenerationConfig(streamReconnect: true),
      );
      final threads = files['api/threads_api.dart']!;
      expect(threads, contains('reconnection: .on,'));
      expect(words(threads), contains(sentence));
      final chat = files['api/chat_api.dart']!;
      expect(chat, contains('reconnection: .off,'));
    });

    test('by its sse.reconnect override is a POST with reconnection on', () {
      final ranges = emitClient(
        'event_ranges.yaml',
        overrides: 'event_ranges.overrides.yaml',
      )['api/ranges_api.dart']!;
      expect(ranges, contains('reconnection: .on,'));
      expect(words(ranges), contains(sentence));
      expect(ranges, isNot(contains('reconnection: .off,')));
    });
  });
}
