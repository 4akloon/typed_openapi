import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

/// The data of one chat event, decoded the way generated code does.
final class Delta {
  const Delta(this.text);

  factory Delta.fromJson(Map<String, Object?> json) => Delta(
    JsonReader(json, schema: 'Delta').required('text', JsonReader.asString),
  );

  /// Decodes the data of one event.
  static Delta fromEvent(SseMessage message) =>
      Delta.fromJson(message.jsonObject);

  final String text;
}

DateTime _parseDate(SseMessage message) => DateTime.parse(message.data);

void main() {
  const decoder = SseItemDecoder<Delta>(Delta.fromEvent);

  String describe(SseItem<Delta> item) => switch (item) {
    SseEvent(:final data, :final event, :final id) => '$event $id ${data.text}',
    SseDecodeError(:final error, :final message) =>
      'error ${message.data} ${error.pointer}',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  test('events decode, a bad event does not stop the stream', () async {
    final items = await decoder
        .bind(
          Stream.value(
            utf8.encode(
              'id: 1\ndata: {"text": "a"}\n\n'
              'data: {"text": 2}\n\n'
              'data: [DONE]\n\n'
              'event: delta\ndata: {"text": "b"}\n\n',
            ),
          ),
        )
        .toList();
    expect(items.map(describe), [
      'message 1 a',
      'error {"text": 2} /text',
      'error [DONE] ',
      'delta 1 b',
      'end closed',
    ]);
  });

  test('a FormatException of the decoder is an item, not an error', () async {
    // A user converter or Date.parse rejecting the data of one event.
    const dates = SseItemDecoder<DateTime>(_parseDate);
    final errors = <Object>[];
    final items = await runZonedGuarded(
      () => dates
          .bind(
            Stream.value(
              utf8.encode(
                'data: 2024-01-01T00:00:00Z\n\n'
                'data: soon\n\n'
                'data: 2025-01-01T00:00:00Z\n\n',
              ),
            ),
          )
          .toList(),
      (error, _) => errors.add(error),
    );
    expect(errors, isEmpty);
    expect(
      items!.map(
        (item) => switch (item) {
          SseEvent() => 'event',
          SseDecodeError() => 'decode error',
          SseDisconnected() => 'disconnected',
        },
      ),
      ['event', 'decode error', 'event', 'disconnected'],
    );
    final failed = items[1] as SseDecodeError<DateTime>;
    expect(failed.message.data, 'soon');
    expect(failed.error.pointer, '');
    expect(failed.error.expected, 'a value its decoder accepts');
  });

  test('an Error of the decoder still reaches the listener', () async {
    final seen = <Object>[];
    final done = Completer<void>();
    SseItemDecoder<int>((_) => throw StateError('bug'))
        .bind(Stream.value(utf8.encode('data: x\n\n')))
        .listen(
          (_) {},
          onError: seen.add,
          onDone: done.complete,
        );
    await done.future;
    expect(seen.single, isA<StateError>());
  });

  test('a stream error is the last item and closes the stream', () async {
    final source = StreamController<List<int>>();
    final items = <SseItem<Delta>>[];
    final done = Completer<void>();
    decoder
        .bind(source.stream)
        .listen(
          items.add,
          onError: (Object e) => fail('unexpected error $e'),
          onDone: done.complete,
        );
    source
      ..add(utf8.encode('data: {"text": "a"}\n\n'))
      ..addError(StateError('connection lost'))
      ..add(utf8.encode('data: {"text": "late"}\n\n'));
    await done.future;
    expect(items.map(describe), [
      'message  a',
      'end Bad state: connection lost',
    ]);
    expect((items.last as SseDisconnected).stackTrace, isNotNull);
    await source.close();
  });

  test('cancelling the items cancels the body', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final first = Completer<SseItem<Delta>>();
    final subscription = decoder.bind(source.stream).listen(first.complete);
    source.add(utf8.encode('data: {"text": "a"}\n\n'));
    expect(describe(await first.future), 'message  a');
    await subscription.cancel();
    expect(cancelled, isTrue);
    await source.close();
  });

  group('onClose is called exactly once', () {
    Future<int> closes(
      Delta Function(SseMessage) decode,
      void Function(StreamController<List<int>> source) drive, {
      bool cancelAtEnd = false,
    }) async {
      var calls = 0;
      final source = StreamController<List<int>>();
      final done = Completer<void>();
      final subscription = SseItemDecoder<Delta>(decode, onClose: () => calls++)
          .bind(source.stream)
          .listen((_) {}, onError: (Object _) {}, onDone: done.complete);
      drive(source);
      await done.future;
      if (cancelAtEnd) await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      await source.close();
      return calls;
    }

    final event = utf8.encode('data: {"text": "a"}\n\n');

    test('when the body ends', () async {
      expect(
        await closes(Delta.fromEvent, (s) {
          s
            ..add(event)
            ..close();
        }),
        1,
      );
    });

    test('when the body ends and the listener cancels afterwards', () async {
      expect(
        await closes(Delta.fromEvent, (s) {
          s
            ..add(event)
            ..close();
        }, cancelAtEnd: true),
        1,
      );
    });

    test('when the body fails', () async {
      expect(
        await closes(Delta.fromEvent, (s) {
          s
            ..add(event)
            ..addError(StateError('x'));
        }),
        1,
      );
    });

    test('when the decoder throws an Error', () async {
      expect(
        await closes((_) => throw StateError('bug'), (s) => s.add(event)),
        1,
      );
    });

    test('when the listener cancels, however often', () async {
      var calls = 0;
      final source = StreamController<List<int>>();
      final subscription = SseItemDecoder<Delta>(
        Delta.fromEvent,
        onClose: () => calls++,
      ).bind(source.stream).listen((_) {});
      await subscription.cancel();
      await subscription.cancel();
      expect(calls, 1);
      await source.close();
    });
  });

  test('items describe themselves', () {
    const message = SseMessage(data: 'x', event: 'e');
    final error = JsonDecodeException(expected: 'a', actual: 'b');
    expect(
      '${const SseEvent<int>(1, event: 'e', id: '3')}',
      'SseEvent(e, id: 3)',
    );
    expect(
      '${SseDecodeError<int>(error, message)}',
      'SseDecodeError(e: JsonDecodeException: expected a, got b)',
    );
    expect(
      '${const SseDisconnected<int>()}',
      'SseDisconnected(closed by server)',
    );
  });
}
