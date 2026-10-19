import 'dart:convert';
import 'dart:typed_data';

import '../json/json_decode_exception.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../transport/cancel_signal.dart';
import '../transport/transport_exception.dart';

/// Turns what a transport gives `ClientSender` (a response, or a
/// [TransportException]) into a [Result].
final class ClientResults {
  /// Creates the mapping.
  const ClientResults();

  /// [raw] decoded with [decode]; a [JsonDecodeException] or a
  /// [FormatException] it throws is a [DecodeError].
  Result<T, E> decode<T, E>(
    RawResponse raw,
    Result<T, E> Function(RawResponse response) decode,
  ) {
    try {
      return decode(raw);
    } on JsonDecodeException catch (e) {
      return decodeError(e, raw.statusCode, raw.body, raw.headers);
    } on FormatException catch (e) {
      // A user converter (R6.8) or `Date.parse` rejecting server data.
      return decodeError(
        JsonDecodeException.fromFormatException(e),
        raw.statusCode,
        raw.body,
        raw.headers,
      );
    }
  }

  /// The [DecodeError] of a body that did not read or decode; [body] is
  /// kept, as text when it is bytes.
  DecodeError<T, E> decodeError<T, E>(
    JsonDecodeException error,
    int statusCode,
    Object? body,
    Map<String, List<String>> headers,
  ) => DecodeError(
    error,
    statusCode: statusCode,
    rawBody: switch (body) {
      final Uint8List bytes => utf8.decode(bytes, allowMalformed: true),
      final other => other,
    },
    headers: headers,
  );

  /// The failure of [exception]: [Cancelled] for a cancel, else
  /// [TransportError].
  Failure<T, E> failure<T, E>(
    TransportException exception,
    StackTrace stackTrace,
  ) => switch (exception.kind) {
    .cancelled => Cancelled(exception, exception.stackTrace ?? stackTrace),
    _ => TransportError(exception, exception.stackTrace ?? stackTrace),
  };

  /// The failure of an [Exception] that is not a [TransportException],
  /// raised while a body was read: a transport failure of kind
  /// [TransportExceptionKind.other] whose cause it is.
  Failure<T, E> unexpected<T, E>(Exception exception, StackTrace stackTrace) =>
      TransportError(
        TransportException(
          .other,
          '$exception',
          cause: exception,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );

  /// The [Cancelled] of a call whose [signal] was cancelled before its
  /// request was sent; the transport is not called.
  Failure<T, E> cancelledBefore<T, E>(CancelSignal signal) {
    final stackTrace = StackTrace.current;
    return Cancelled(
      TransportException(
        .cancelled,
        'The call was cancelled before it was sent.',
        cause: signal.reason,
        stackTrace: stackTrace,
      ),
      stackTrace,
    );
  }
}
