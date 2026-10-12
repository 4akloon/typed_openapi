import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';

/// The data of one event.
final class Delta {
  const Delta(this.text);

  /// Decodes the data of one event, as generated code does.
  static Delta fromEvent(SseMessage message) => Delta(
    JsonReader(
      message.jsonObject,
      schema: 'Delta',
    ).required('text', JsonReader.asString),
  );

  final String text;
}

/// A documented error body.
final class Problem {
  const Problem(this.code);

  factory Problem.fromJson(Map<String, Object?> json) => Problem(
    JsonReader(json, schema: 'Problem').required('code', JsonReader.asString),
  );

  final String code;
}

void main() {
  const chat = OperationRequest(
    OperationInfo(operationId: 'chat', method: 'POST', pathTemplate: '/chat'),
    body: {'prompt': 'hi'},
    contentType: 'application/json',
    streamStatuses: {200},
  );

  Result<Stream<SseItem<Delta>>, Problem> decodeError(RawResponse r) =>
      switch (r.statusCode) {
        404 => r.error(Problem.fromJson(r.jsonObject)),
        _ => r.undocumented(),
      };

  Future<Result<Stream<SseItem<Delta>>, Problem>> open(
    FakeAdapter adapter, {
    CallOptions? call,
  }) => DioRequestSender(Dio()..httpClientAdapter = adapter).openEvents(
    chat,
    Delta.fromEvent,
    decodeError,
    call: call,
  );

  ResponseBody eventStream(Stream<Uint8List> body, [int status = 200]) =>
      ResponseBody(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );

  String describe(SseItem<Delta> item) => switch (item) {
    SseEvent(:final data) => data.text,
    SseDecodeError(:final error) => 'error ${error.pointer}',
    SseDisconnected(cause: final DioException cause) =>
      'end ${cause.type.name}',
    SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
  };

  test('a 2xx opens a stream of decoded events', () async {
    final adapter = FakeAdapter(
      (_) => eventStream(
        Stream.value(
          utf8.encode(
            'data: {"text": "a"}\n\ndata: {}\n\ndata: {"text": "b"}\n\n',
          ),
        ),
      ),
    );
    final result = await open(adapter);
    final success = result as Success<Stream<SseItem<Delta>>, Problem>;
    expect(success.statusCode, 200);
    expect((await success.data.toList()).map(describe), [
      'a',
      'error /text',
      'b',
      'end closed',
    ]);
    final sent = adapter.requests.single;
    expect(sent.headers['Accept'], 'text/event-stream');
    expect(sent.responseType, ResponseType.stream);
    expect(OperationInfo.of(sent)?.operationId, 'chat');
    expect(adapter.bodies.single, '{"prompt":"hi"}');
  });

  test('a dropped connection is the last item, not an error', () async {
    final body = StreamController<Uint8List>();
    final result = await open(FakeAdapter((_) => eventStream(body.stream)));
    final items = <String>[];
    final done = Completer<void>();
    (result as Success<Stream<SseItem<Delta>>, Problem>).data.listen(
      (item) => items.add(describe(item)),
      onError: (Object e) => fail('unexpected error $e'),
      onDone: done.complete,
    );
    body
      ..add(utf8.encode('data: {"text": "a"}\n\n'))
      ..addError(StateError('socket closed'));
    await done.future;
    expect(items, ['a', 'end Bad state: socket closed']);
    await body.close();
  });

  test('cancelling the request ends the stream with the cancel', () async {
    final body = StreamController<Uint8List>();
    final token = CancelToken();
    final result = await open(
      FakeAdapter((_) => eventStream(body.stream)),
      call: CallOptions(cancelToken: token),
    );
    final items = (result as Success<Stream<SseItem<Delta>>, Problem>).data
        .map(describe)
        .toList();
    body.add(utf8.encode('data: {"text": "a"}\n\n'));
    await Future<void>.delayed(Duration.zero);
    token.cancel('user left');
    expect(await items, ['a', 'end cancel']);
    await body.close();
  });

  test('error statuses read the whole body and decode it', () async {
    ResponseBody errorBody(int status, String text, String type) =>
        ResponseBody(
          Stream.value(Uint8List.fromList(utf8.encode(text))),
          status,
          headers: {
            Headers.contentTypeHeader: [type],
          },
        );

    final documented = await open(
      FakeAdapter(
        (_) => errorBody(404, '{"code": "NO_MODEL"}', 'application/json'),
      ),
    );
    expect(
      (documented as HttpError<Stream<SseItem<Delta>>, Problem>).body.code,
      'NO_MODEL',
    );

    final undocumented = await open(
      FakeAdapter((_) => errorBody(502, 'Bad gateway', 'text/html')),
    );
    expect(
      (undocumented as UndocumentedStatus).rawBody,
      'Bad gateway',
    );

    final malformed = await open(
      FakeAdapter((_) => errorBody(404, '{"code":', 'application/json')),
    );
    final error = malformed as DecodeError;
    expect((error.statusCode, error.rawBody), (404, '{"code":'));

    final mismatch = await open(
      FakeAdapter((_) => errorBody(404, '{"code": 1}', 'application/json')),
    );
    expect((mismatch as DecodeError).error.pointer, '/code');
  });

  test('cancelling the subscription closes the connection', () async {
    final body = StreamController<Uint8List>();
    final adapter = FakeAdapter((_) => eventStream(body.stream));
    final result = await open(adapter);
    final items = <String>[];
    final subscription = (result as Success<Stream<SseItem<Delta>>, Problem>)
        .data
        .listen(
          (item) => items.add(describe(item)),
        );
    body.add(utf8.encode('data: {"text": "a"}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(adapter.cancelsFired.single, isFalse);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.cancelsFired.single, isTrue);
    expect(items, ['a']);
    await body.close();
  });

  test('a user cancel still ends the stream with SseDisconnected', () async {
    final body = StreamController<Uint8List>();
    final token = CancelToken();
    final adapter = FakeAdapter((_) => eventStream(body.stream));
    final result = await open(adapter, call: CallOptions(cancelToken: token));
    final items = (result as Success<Stream<SseItem<Delta>>, Problem>).data
        .map(describe)
        .toList();
    token.cancel();
    expect(await items, ['end cancel']);
    expect(adapter.cancelsFired.single, isTrue);
    await body.close();
  });

  test('a token cancelled before the call is Cancelled', () async {
    final token = CancelToken()..cancel();
    final adapter = FakeAdapter(
      (_) => eventStream(Stream.value(utf8.encode('data: {}\n\n'))),
    );
    final result = await open(adapter, call: CallOptions(cancelToken: token));
    expect(result, isA<Cancelled>());
  });

  test('a body read failure on an error status is a TransportError', () async {
    final body = StreamController<Uint8List>();
    final pending = open(
      FakeAdapter(
        (_) => ResponseBody(
          body.stream,
          500,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      ),
    );
    body
      ..add(utf8.encode('partial'))
      ..addError(const SocketException('reset'));
    final result = await pending;
    final exception = (result as TransportError).exception;
    expect(exception.type, DioExceptionType.unknown);
    expect(exception.error, isA<SocketException>());
    await body.close();
  });

  test('an Error while reading the body still propagates', () async {
    final body = StreamController<Uint8List>();
    final pending = open(
      FakeAdapter((_) => ResponseBody(body.stream, 500)),
    );
    body.addError(StateError('bug'));
    await expectLater(pending, throwsStateError);
    await body.close();
  });

  test('an Error in decodeEvent is a stream error and closes it', () async {
    final body = StreamController<Uint8List>();
    final adapter = FakeAdapter((_) => eventStream(body.stream));
    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
        .openEvents<Delta, Problem>(
          chat,
          (message) => throw StateError('bug'),
          decodeError,
        );
    final items = <SseItem<Delta>>[];
    final errors = <Object>[];
    final done = Completer<void>();
    (result as Success<Stream<SseItem<Delta>>, Problem>).data.listen(
      items.add,
      onError: errors.add,
      onDone: done.complete,
    );
    body.add(utf8.encode('data: {"text": "a"}\n\ndata: {"text": "b"}\n\n'));
    await done.future;
    await Future<void>.delayed(Duration.zero);
    expect(items, isEmpty);
    expect(errors.single, isA<StateError>());
    expect(adapter.cancelsFired.single, isTrue);
    await body.close();
  });

  test('a status outside streamStatuses is decoded like a response', () async {
    final result = await open(
      FakeAdapter(
        (_) => eventStream(
          Stream.value(utf8.encode('data: {"text": "a"}\n\n')),
          201,
        ),
      ),
    );
    final undocumented = result as UndocumentedStatus;
    expect(undocumented.statusCode, 201);
    expect(undocumented.rawBody, 'data: {"text": "a"}\n\n');
  });

  test('transport failures before the stream opens', () async {
    final result = await open(
      FakeAdapter(
        (o) => throw DioException.connectionError(
          requestOptions: o,
          reason: 'refused',
        ),
      ),
    );
    expect(
      (result as TransportError).exception.type,
      DioExceptionType.connectionError,
    );
  });

  test(
    'on the web the default adapter is refused with an explanation',
    () async {
      final web = DioRequestSender(Dio(), isWeb: true);
      final result = await web.openEvents(chat, Delta.fromEvent, decodeError);
      final error = result as TransportError;
      expect(error.exception.message, DioRequestSender.webStreamingMessage);
      expect(error.exception.error, isA<UnsupportedError>());
      expect(
        OperationInfo.of(error.exception.requestOptions)?.operationId,
        'chat',
      );

      final adapter = FakeAdapter(
        (_) =>
            eventStream(Stream.value(utf8.encode('data: {"text": "a"}\n\n'))),
      );
      final custom = DioRequestSender(
        Dio()..httpClientAdapter = adapter,
        isWeb: true,
      );
      final opened = await custom.openEvents(
        chat,
        Delta.fromEvent,
        decodeError,
      );
      expect(opened, isA<Success<Stream<SseItem<Delta>>, Problem>>());
    },
  );
}
