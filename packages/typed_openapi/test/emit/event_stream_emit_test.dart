@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
      "    '' => const FeedEventEvent1(),",
      "    '*/' => FeedEventEvent2(message.data),",
      r"    '\$cost' => FeedEventCost(message.data),",
      r"    'a\nb' => FeedEventAB(message.data),",
      r"    '\u{202e}evil' => FeedEventEvil(message.data),",
      "    'unknown' => FeedEventUnknown2(message.data),",
      "    'delta' => FeedEventDelta2(message.data),",
      '/// The event with an empty name of [DefaultApi.feed], which has no data.',
      "  String toString() => 'FeedEventSecret(<redacted>)';",
      r"  String toString() => 'FeedEventUnknown($event, <redacted>)';",
    ]) {
      expect(feed, contains(pattern));
    }
    expect(feed, isNot(contains('\u202E')));
  });

  test('text events are the data as it is', () {
    expect(threads, contains('Stream<SseItem<String>>'));
    expect(threads, contains('(m) => m.data,'));
  });
}
