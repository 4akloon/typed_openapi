import '../request/body_encoder.dart';
import '../request/encoded_body.dart';
import '../request/operation_request.dart';
import '../transport/cancel_signal.dart';
import '../transport/transport_request.dart';
import 'call_options.dart';
import 'progress_counter.dart';

/// Builds the [TransportRequest] of an [OperationRequest]: the target, the
/// headers in order and the body bytes. It sets `Accept`, the operation's
/// headers, `Content-Type` and `Content-Length`, and nothing else besides
/// the client's default headers and the call's own.
///
/// A header is set by the first of these that has it, from the last to the
/// first: the call's headers, the operation's (and the stream's
/// `Last-Event-ID`), the client's [defaultHeaders].
final class RequestBuilder {
  /// Creates the builder, which encodes bodies with [encoder] and sends
  /// [defaultHeaders] when neither the operation nor the call sets them.
  const RequestBuilder(this.encoder, {this.defaultHeaders = const {}});

  /// Encodes request bodies.
  final BodyEncoder encoder;

  /// The headers of the client's defaults (`CallOptions.headers`), under
  /// the operation's. A call that gives a name a `null` removes it here.
  final Map<String, Object?> defaultHeaders;

  /// The request of [request] with [call], whose headers are the call's own
  /// (not merged with the defaults'): for an event stream ([events])
  /// with `Accept: text/event-stream` and, when it is not empty and a valid
  /// header value, [lastEventId] as `Last-Event-ID`. [cancel] wins over the
  /// call's signal.
  ///
  /// Throws what encoding the body throws ([ArgumentError],
  /// [FormatException]) and [ArgumentError] for a path without a value.
  TransportRequest build(
    OperationRequest request,
    CallOptions? call, {
    bool events = false,
    CancelSignal? cancel,
    String lastEventId = '',
  }) {
    final body = encoder.encode(request);
    final headers = _headers(request, call, body, events, lastEventId);
    return TransportRequest(
      method: request.operation.method,
      target: request.resolvePath(),
      operation: request.operation,
      headers: headers,
      body: switch (body) {
        final body? => ProgressCounter(
          call?.onSendProgress,
        ).count(body.read(), body.length),
        null => null,
      },
      cancel: cancel ?? call?.cancel,
      extra: {...?call?.extra},
      isEventStream: events,
    );
  }

  /// The headers of [request]: `Accept`, the operation's, the defaults'
  /// that these leave unset, the call's, the stream's `Last-Event-ID`, then
  /// the body's type and length.
  Map<String, List<String>> _headers(
    OperationRequest request,
    CallOptions? call,
    EncodedBody? body,
    bool events,
    String lastEventId,
  ) {
    final headers = _HeaderList()
      ..add('Accept', events ? 'text/event-stream' : request.accept);
    for (final MapEntry(:key, :value) in request.resolveHeaders().entries) {
      headers.add(key, value);
    }
    final callNames = {
      for (final name in call?.headers.keys ?? const <String>[])
        name.toLowerCase(),
    };
    for (final MapEntry(:key, :value) in defaultHeaders.entries) {
      final isReplaced =
          callNames.contains(key.toLowerCase()) ||
          (events && _isLastEventId(key));
      if (!isReplaced) headers.addIfAbsent(key, value);
    }
    for (final MapEntry(:key, :value) in call?.headers.entries ?? const []) {
      // The stream's last event id replaces the user's `Last-Event-ID`.
      if (!events || !_isLastEventId(key)) headers.add(key, value);
    }
    if (events && _isHeaderValue(lastEventId)) {
      headers.add('Last-Event-ID', lastEventId);
    }
    if (body?.contentType case final type?) {
      headers
        ..remove('content-type')
        ..add('content-type', type);
    }
    if (body != null) headers.add('content-length', '${body.length}');
    return headers.values;
  }

  /// The `Last-Event-ID` that the user's [headers] set (in any case), which
  /// is where the stream's last event id starts: it is sent with the first
  /// request, the ids of the events replace it, and an `id:` that resets it
  /// leaves it gone, as `EventSource` does. Empty when there is none.
  static String userLastEventId(Map<String, Object?>? headers) {
    for (final MapEntry(:key, :value) in headers?.entries ?? const []) {
      if (_isLastEventId(key) && value != null) return '$value';
    }
    return '';
  }

  static bool _isLastEventId(String header) =>
      header.toLowerCase() == 'last-event-id';

  /// Whether [id] is a non-empty header value that every HTTP client sends:
  /// printable ASCII, spaces and tabs. The VM's `HttpClient` throws on any
  /// other character, which would fail every reconnection; a browser sends
  /// UTF-8, so the id is dropped on both and the stream reconnects without
  /// `Last-Event-ID`.
  static bool _isHeaderValue(String id) =>
      id.isNotEmpty &&
      id.codeUnits.every((c) => c == 0x09 || (c >= 0x20 && c <= 0x7E));
}

/// Headers by name, case-insensitively: a name keeps its first spelling and
/// place, and a later value replaces an earlier one, as Dio's header map
/// did.
final class _HeaderList {
  final Map<String, (String, List<String>)> _byName = {};

  /// Sets [name] to [value]: nothing for `null`, one value per item of a
  /// list, else its text.
  void add(String name, Object? value) {
    final values = switch (value) {
      null => null,
      final List<Object?> items => [for (final item in items) '$item'],
      final other => ['$other'],
    };
    if (values == null) return;
    final key = name.toLowerCase();
    _byName[key] = (_byName[key]?.$1 ?? name, values);
  }

  /// Sets [name] like [add] unless a value is there already.
  void addIfAbsent(String name, Object? value) {
    if (!_byName.containsKey(name.toLowerCase())) add(name, value);
  }

  /// Removes [name] in any case.
  void remove(String name) => _byName.remove(name.toLowerCase());

  /// The headers, by their first spelling.
  Map<String, List<String>> get values => {
    for (final (name, values) in _byName.values) name: values,
  };
}
