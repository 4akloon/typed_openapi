import 'dart:async';
import 'dart:convert';
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
