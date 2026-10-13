import '../model/spec_node.dart';
import 'api_ir.dart';
import 'errors_ir.dart';
import 'event_stream_ir.dart';
import 'parameter_ir.dart';
import 'request_body_ir.dart';
import 'response_ir.dart';

export 'event_stream_ir.dart';
export 'event_union_ir.dart';
export 'event_variant_ir.dart';
export 'stream_reconnection.dart';

/// An operation: one method of a group.
final class OperationIr {
  /// Creates an operation.
  const OperationIr({
    required this.location,
    required this.name,
    required this.method,
    required this.path,
    required this.parameters,
    required this.responses,
    required this.errors,
    this.operationId,
    this.tags = const [],
    this.body,
    this.summary,
    this.description,
    this.deprecated = false,
    this.security = const [],
    this.successType,
    this.errorType,
    this.partsName,
    this.events,
    this.accept,
  });

  /// This operation with the names of the types the API emitter declares
  /// for it, given after the declarations.
  OperationIr withTypes({
    StatusTypeIr? successType,
    StatusTypeIr? errorType,
    String? partsName,
    EventStreamIr? events,
  }) => OperationIr(
    location: location,
    name: name,
    method: method,
    path: path,
    parameters: parameters,
    responses: responses,
    errors: errors,
    operationId: operationId,
    tags: tags,
    body: body,
    summary: summary,
    description: description,
    deprecated: deprecated,
    security: security,
    successType: successType,
    errorType: errorType,
    partsName: partsName,
    events: events ?? this.events,
    accept: accept,
  );

  /// Where the Operation Object is.
  final SpecLocation location;

  /// The Dart name of the method.
  final String name;

  /// The HTTP method, upper case.
  final String method;

  /// The path template.
  final String path;

  /// `operationId`, as in the spec.
  final String? operationId;

  /// `tags`, as in the spec.
  final List<String> tags;

  /// The parameters: path, query, header, cookie, in the spec's order with
  /// the path item's first.
  final List<ParameterIr> parameters;

  /// The request body.
  final RequestBodyIr? body;

  /// The responses, by status as in the spec.
  final List<ResponseIr> responses;

  /// The type of documented errors (R11.4).
  final ErrorsIr errors;

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;

  /// The security requirements (R10.8): the operation's `security`, else
  /// the document's. Any one alternative is enough; every scheme of an
  /// alternative is needed; an empty alternative makes security optional.
  final List<List<SecurityUseIr>> security;

  /// The sealed type of the successes, when 2xx responses have different
  /// bodies (decision 18 of M8). Without it the success type is the one
  /// body type, `void` without a body, and `JsonValue` when no 2xx is
  /// documented (TOA653).
  final StatusTypeIr? successType;

  /// The sealed type of the errors, for [ErrorsByStatus].
  final StatusTypeIr? errorType;

  /// The class of the parts of a multipart body ([RequestBodyIr.parts]).
  final String? partsName;

  /// The events, when the method returns an event stream: its successes
  /// with a body are `text/event-stream` and their type is the type of
  /// each event's data.
  final EventStreamIr? events;

  /// The media type the method asks for with `Accept`: set on the method that
  /// returns the body of an operation that also has an event-stream method
  /// (decision 5 of M10), so the server does not answer with the stream.
  final String? accept;

  /// The key of the operation in the overrides file: its `operationId`,
  /// or `METHOD /path`.
  String get overrideKey => operationId ?? '$method $path';

  /// The responses with a 2xx status.
  List<ResponseIr> get successes => [
    for (final response in responses)
      if (response.isSuccess) response,
  ];
}
