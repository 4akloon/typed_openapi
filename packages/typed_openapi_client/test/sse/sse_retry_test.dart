import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  final decode = JsonDecodeException(expected: 'e', actual: 'a');
  Failure<Object?, Object?> transport(TransportExceptionKind kind) =>
      TransportError(TransportException(kind, 'x'), StackTrace.empty);

  final cases = <(String, Failure<Object?, Object?>, bool)>[
    ('connection', transport(.connection), true),
    ('timeout', transport(.timeout), true),
    ('other', transport(.other), false),
    (
      'cancelled',
      const Cancelled(TransportException(.cancelled, 'x'), StackTrace.empty),
      false,
    ),
    for (final status in [408, 429, 500, 502, 503, 504, 599]) ...[
      ('HttpError $status', HttpError('x', statusCode: status), true),
      (
        'UndocumentedStatus $status',
        UndocumentedStatus(statusCode: status),
        true,
      ),
      ('DecodeError $status', DecodeError(decode, statusCode: status), true),
    ],
    for (final status in [
      501,
      505,
      400,
      401,
      403,
      404,
      409,
      410,
      422,
      200,
      302,
    ]) ...[
      ('HttpError $status', HttpError('x', statusCode: status), false),
      (
        'UndocumentedStatus $status',
        UndocumentedStatus(statusCode: status),
        false,
      ),
      ('DecodeError $status', DecodeError(decode, statusCode: status), false),
    ],
    ('DecodeError without status', DecodeError(decode), false),
  ];

  for (final (name, failure, expected) in cases) {
    test('$name is ${expected ? 'transient' : 'final'}', () {
      expect(SseRetry.isTransient(failure), expected);
    });
  }
}
