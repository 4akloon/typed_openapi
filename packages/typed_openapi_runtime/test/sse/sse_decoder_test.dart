import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  Future<List<SseMessage>> decode(List<Object> chunks) => Stream.fromIterable([
    for (final chunk in chunks)
      switch (chunk) {
        final String text => utf8.encode(text),
        _ => chunk as List<int>,
      },
  ]).transform(const SseDecoder()).toList();

  Future<List<String>> data(String stream) async => [
    for (final e in await decode([stream])) e.data,
  ];

  group('WHATWG examples', () {
    test('multi-line data is joined by newlines', () async {
      expect(await data('data: YHOO\ndata: +2\ndata: 10\n\n'), [
        'YHOO\n+2\n10',
      ]);
    });

    test('comments, ids and the optional space after the colon', () async {
      final events = await decode([
        ': test stream\n\ndata: first event\nid: 1\n\n'
            'data:second event\nid\n\ndata:  third event\n\n',
      ]);
      expect(events, const [
        SseMessage(data: 'first event', id: '1'),
        SseMessage(data: 'second event'),
        SseMessage(data: ' third event'),
      ]);
    });

    test('empty data lines and an unfinished last event', () async {
      expect(await data('data\n\ndata\ndata\n\ndata:'), ['', '\n']);
    });

    test('a space after the colon is optional', () async {
      expect(await data('data:test\n\ndata: test\n\n'), ['test', 'test']);
    });
  });

  group('line endings and encoding', () {
    test('CRLF, LF and CR all end lines', () async {
      expect(await data('data: a\r\n\r\ndata: b\n\ndata: c\r\rdata: d\r\n\n'), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('CR and LF in different chunks are one line ending', () async {
      final events = await decode(['data: a\r', '\ndata: b\r', '\n\r', '\n']);
      expect(events.single.data, 'a\nb');
    });

    test('a character split between chunks stays whole', () async {
      final bytes = utf8.encode('data: ü€\n\n');
      final events = await decode([bytes.sublist(0, 7), bytes.sublist(7)]);
      expect(events.single.data, 'ü€');
    });

    test('a leading BOM is dropped, invalid UTF-8 is replaced', () async {
      final events = await decode([
        [0xEF, 0xBB, 0xBF],
        'data: x\n\n',
        [0x64, 0x61, 0x74, 0x61, 0x3A, 0xFF, 0x0A, 0x0A],
      ]);
      expect([for (final e in events) e.data], ['x', '�']);
    });

    test('a second BOM is data: it spoils the field name', () async {
      expect(
        await decode([
          [0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF],
          'data: a\n\n',
        ]),
        isEmpty,
      );
    });

    test('CR, an empty chunk and LF are one line ending', () async {
      final events = await decode(['data: a\r', <int>[], '\n\n']);
      expect([for (final e in events) e.data], ['a']);
    });

    test('a Stream<Uint8List>, as Dio gives, is accepted', () async {
      final events = await const SseDecoder()
          .bind(
            Stream<Uint8List>.value(
              Uint8List.fromList(utf8.encode('data: x\n\n')),
            ),
          )
          .toList();
      expect(events.single.data, 'x');
    });

    test('a BOM after the start is data', () async {
      expect(await data('data: ﻿x\n\n'), ['﻿x']);
    });
  });

  group('fields', () {
    test('event sets the type of one event only', () async {
      final events = await decode([
        'event: add\ndata: 1\n\ndata: 2\n\nevent: x\n\ndata: 3\n\n',
      ]);
      expect([for (final e in events) e.event], ['add', 'message', 'message']);
    });

    test('id persists across events; an id with NUL is ignored', () async {
      final events = await decode([
        'id: 7\ndata: a\n\ndata: b\n\nid: 8\u0000\ndata: c\n\nid\ndata: d\n\n',
      ]);
      expect([for (final e in events) e.id], ['7', '7', '7', '']);
    });

    test('retry takes ASCII digits only and persists', () async {
      final events = await decode([
        'retry: 1500\n\ndata: a\n\nretry: 2s\ndata: b\n\n'
            'retry: 99999999999999999999999\ndata: c\n\n',
      ]);
      expect(
        [for (final e in events) e.retry],
        [
          const Duration(milliseconds: 1500),
          const Duration(milliseconds: 1500),
          const Duration(milliseconds: 1500),
        ],
      );
    });

    test('a retry beyond the JavaScript-safe cap is ignored', () async {
      final events = await decode([
        'retry: 9223372036854775807\ndata: a\n\n'
            'retry: 9007199254741\ndata: b\n\n'
            'retry: ${'9' * 30}\ndata: c\n\n'
            'retry: 9007199254740\ndata: d\n\n',
      ]);
      expect(
        [for (final e in events) e.retry],
        [
          null,
          null,
          null,
          const Duration(milliseconds: 9007199254740),
        ],
      );
    });

    test('unknown fields and blank blocks dispatch nothing', () async {
      expect(await decode(['foo: bar\n\n\n\n: ping\n\n']), isEmpty);
      expect(await data('foo: bar\ndata: x\n\n'), ['x']);
    });
  });

  test(
    'stream errors pass through and each stream has its own state',
    () async {
      final controller = StreamController<List<int>>();
      final events = <String>[];
      final errors = <Object>[];
      final done = Completer<void>();
      controller.stream
          .transform(const SseDecoder())
          .listen(
            (e) => events.add(e.data),
            onError: errors.add,
            onDone: done.complete,
          );
      controller
        ..add(utf8.encode('id: 1\ndata: a\n\n'))
        ..addError(StateError('connection lost'))
        ..add(utf8.encode('data: b\n\n'));
      await controller.close();
      await done.future;
      expect(events, ['a', 'b']);
      expect(errors.single, isA<StateError>());
      final fresh = await decode(['data: c\n\n']);
      expect(fresh.single.id, '');
    },
  );

  test('events have value equality and a readable form', () {
    const event = SseMessage(data: 'x', event: 't', id: '1');
    expect(event, const SseMessage(data: 'x', event: 't', id: '1'));
    expect(
      event.hashCode,
      const SseMessage(data: 'x', event: 't', id: '1').hashCode,
    );
    expect(event, isNot(const SseMessage(data: 'x')));
    expect('$event', 'SseMessage(event: t, data: x, id: 1, retry: null)');
  });

  test('data parses as JSON or reports why not', () {
    expect(const SseMessage(data: '{"a": [1]}').jsonObject, {
      'a': [1],
    });
    expect(const SseMessage(data: '["DONE"]').json, ['DONE']);
    JsonDecodeException failure(Object? Function() read) {
      try {
        read();
      } on JsonDecodeException catch (e) {
        return e;
      }
      fail('expected a JsonDecodeException');
    }

    expect(
      failure(() => const SseMessage(data: '[DONE]').json).message,
      'expected JSON event data, got text that is not JSON',
    );
    expect(
      failure(() => const SseMessage(data: '1').jsonObject).actual,
      'a number',
    );
    expect(
      failure(() => SseMessage(data: '[' * 1001 + ']' * 1001).json).path,
      hasLength(1000),
    );
  });
}
