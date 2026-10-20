import 'package:meta/meta.dart';

import '../sse/sse_options.dart';
import '../transport/cancel_signal.dart';

/// Per-call options: the optional `call` parameter of every generated
/// method.
///
/// One object instead of many named parameters, so that a new option does
/// not change the signature of generated methods (and of user fakes that
/// implement them). The base URL and the timeouts and retries of plain
/// requests belong to the transport; an event stream retries its opening and
/// its reconnections itself (see [SseOptions]).
///
/// A client can hold default options (`ClientSender.defaults`); each call's
/// options are merged over them with [merge]: a value the call sets wins,
/// one it leaves unset falls back to the default.
final class CallOptions {
  /// Creates per-call options.
  const CallOptions({
    this.cancel,
    this.headers = const {},
    this.extra = const {},
    this.onSendProgress,
    this.onReceiveProgress,
    this.sse,
  });

  /// Cancels the call; the operation then returns `Cancelled`, and an event
  /// stream ends with `SseDisconnected`.
  ///
  /// As a client's default (`ClientSender.defaults`) the signal is scoped to
  /// the client's lifetime: each call and stream adds a listener to it that
  /// stays until the signal fires, and once it has fired every later call
  /// of the client returns `Cancelled`, since a signal stays cancelled.
  /// Build a new client with a new signal after that. Use it for a
  /// session-scoped client that is thrown away on logout, not for a client
  /// that lives as long as the app and makes unbounded calls.
  final CancelSignal? cancel;

  /// Headers added to the request; a call's win over the headers the
  /// operation sends for its header parameters, case-insensitively, while a
  /// client's defaults (`ClientSender.defaults`) go under them. A value that is a
  /// list is sent as one value per item; a `null` value is not sent. The
  /// one exception is `Content-Type`: the operation's own content type
  /// (`OperationRequest.contentType`, set for a request body) wins over a
  /// `Content-Type` given here, so it cannot be used to pick another media
  /// type such as `application/merge-patch+json`.
  ///
  /// For an event stream a `Last-Event-ID` given here is where the stream's
  /// last event id starts, as it would for `EventSource`: it goes with the
  /// first request and with a reconnection until an event's `id` replaces
  /// it, and an empty `id:` removes it. It is sent only when it is a valid
  /// header value (printable ASCII).
  final Map<String, Object?> headers;

  /// Data for the transport (`TransportRequest.extra`); `typed_openapi_dio`
  /// merges it into `RequestOptions.extra` for interceptors.
  final Map<String, Object?> extra;

  /// Reports the bytes of the request body sent so far and its length.
  final void Function(int count, int total)? onSendProgress;

  /// Reports the bytes of the response body received so far and its
  /// `Content-Length`, `-1` without one.
  final void Function(int count, int total)? onReceiveProgress;

  /// How an event stream reconnects; null for the defaults of
  /// [SseOptions]. Other operations ignore it.
  final SseOptions? sse;

  /// These options as defaults, with the fields [call] sets on top: the
  /// call wins field by field, and a null [call] gives these options.
  ///
  /// - [cancel]: the call's signal, else the default's; they are never
  ///   combined. A default signal is scoped to the client's lifetime (see
  ///   [cancel]): once it fires, every later call returns `Cancelled`.
  /// - [headers]: the union; the call wins per name, case-insensitively,
  ///   and keeps its own spelling. (`ClientSender` does not send this union:
  ///   it puts the default headers under the operation's and the call's
  ///   over them.) A `null` value in the call removes the
  ///   default header and stays in the map as written.
  /// - [extra]: the union; the call wins per key and a `null` is a value.
  /// - [onSendProgress] and [onReceiveProgress]: the call's, else the
  ///   default's.
  /// - [sse]: merged with [SseOptions.merge].
  CallOptions merge(CallOptions? call) {
    if (call == null) return this;
    return CallOptions(
      cancel: call.cancel ?? cancel,
      headers: _mergeHeaders(headers, call.headers),
      extra: {...extra, ...call.extra},
      onSendProgress: call.onSendProgress ?? onSendProgress,
      onReceiveProgress: call.onReceiveProgress ?? onReceiveProgress,
      sse: switch ((sse, call.sse)) {
        (final defaults?, final own) => defaults.merge(own),
        (null, final own) => own,
      },
    );
  }

  /// These options without their [headers]: what a client merges its call
  /// into when it sends the default headers under the operation's.
  @internal
  CallOptions withoutHeaders() => CallOptions(
    cancel: cancel,
    extra: extra,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
    sse: sse,
  );

  static Map<String, Object?> _mergeHeaders(
    Map<String, Object?> defaults,
    Map<String, Object?> call,
  ) {
    final callNames = {for (final name in call.keys) name.toLowerCase()};
    return {
      for (final MapEntry(:key, :value) in defaults.entries)
        if (!callNames.contains(key.toLowerCase())) key: value,
      ...call,
    };
  }
}
