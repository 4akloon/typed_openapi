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
