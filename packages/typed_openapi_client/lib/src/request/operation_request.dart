import '../params/parameters.dart';
import 'file_upload.dart';
import 'form_body.dart';
import 'multipart_body.dart';
import 'operation_info.dart';

/// How the response body is read, by the content type of the spec.
enum ResponseKind {
  /// JSON, parsed by the client when the response names a JSON type.
  json,

  /// Text.
  text,

  /// Raw bytes.
  bytes,
}

/// One call of an operation, independent of the HTTP client: the operation,
/// its parameters in spec order and the body.
final class OperationRequest {
  /// Creates a request of [operation].
  const OperationRequest(
    this.operation, {
    this.path = const [],
    this.query = const [],
    this.headers = const [],
    this.cookies = const [],
    this.body,
    this.contentType,
    this.responseKind = .json,
    this.accept,
    this.streamStatuses = const {},
  });

  /// The operation being called.
  final OperationInfo operation;

  /// The values of the `{name}` placeholders of the path template.
  final List<PathParameter> path;

  /// The query parameters, sent in this order.
  final List<QueryParameter> query;

  /// The header parameters, sent in this order.
  final List<HeaderParameter> headers;

  /// The cookie parameters, sent in one `Cookie` header in this order.
  final List<CookieParameter> cookies;

  /// The body: a JSON value (`toJson()`, also a string, a number or a
  /// boolean), text, a [FormBody], a [MultipartBody] or a [FileUpload];
  /// `null` for no body. The request sender writes a string or `null` as
  /// JSON text (the HTTP client would get them wrong), leaves a map, list,
  /// number or boolean to the HTTP client's JSON encoding and turns the
  /// other bodies into what the HTTP client sends.
  final Object? body;

  /// The `Content-Type` of [body]; `null` for no body. A `null` [body] with
  /// a JSON content type is the JSON value `null`; with another content
  /// type no `Content-Type` is sent.
  final String? contentType;

  /// How the response body is read.
  final ResponseKind responseKind;

  /// The `Accept` of a method that returns the body of an operation that also
  /// has an event-stream method, so a server that picks the representation by
  /// `Accept` does not answer with the stream; `null` sends none. A call's own
  /// `Accept` wins; an event stream asks for `text/event-stream` and ignores
  /// this.
  final String? accept;

  /// For an event-stream operation, the documented success statuses whose
  /// body is the stream; `ClientSender.openEvents` opens the stream for
  /// these only and decodes any other status like a normal response.
  final Set<int> streamStatuses;

  /// The path template with the path parameters substituted and the query
  /// string appended, relative to the base URL of the HTTP client.
  ///
  /// A placeholder without a parameter is a mistake of the calling code and
  /// throws [ArgumentError].
  String resolvePath() {
    final values = {for (final p in path) p.name: p};
    final resolved = operation.pathTemplate.replaceAllMapped(
      pathVariable,
      (match) {
        final name = match[1]!;
        final parameter = values[name];
        if (parameter == null) {
          throw ArgumentError.value(
            operation.pathTemplate,
            'pathTemplate',
            'No value for {$name}',
          );
        }
        return parameter.encode();
      },
    );
    final queryString = [
      for (final q in query) q.encode(),
    ].where((part) => part.isNotEmpty).join('&');
    return queryString.isEmpty ? resolved : '$resolved?$queryString';
  }

  /// The header parameters with a defined value and the `Cookie` header, in
  /// order.
  Map<String, String> resolveHeaders() {
    final cookie = [
      for (final c in cookies) ?c.encode(),
    ].join('; ');
    return {
      for (final h in headers) h.name: ?h.encode(),
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  /// A variable of a path template: `{name}`, where the name has no brace.
  /// The generator reads templates with the same pattern, so an operation
  /// it generates has a parameter for every variable this finds.
  static final RegExp pathVariable = RegExp(r'\{([^{}]*)\}');
}
