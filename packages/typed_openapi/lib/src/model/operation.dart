import 'parameter.dart';
import 'request_body.dart';
import 'response.dart';
import 'security_requirement.dart';
import 'server.dart';
import 'spec_node.dart';

export 'example.dart';
export 'header.dart';
export 'media_type.dart';
export 'parameter.dart';
export 'path_item.dart';
export 'request_body.dart';
export 'response.dart';
export 'security_requirement.dart';
export 'server.dart';

/// An Operation Object.
final class Operation extends SpecNode {
  /// Creates an operation.
  const Operation({
    required super.location,
    this.tags = const [],
    this.summary,
    this.description,
    this.operationId,
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.deprecated = false,
    this.security,
    this.servers = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// `tags`.
  final List<String> tags;

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `operationId`.
  final String? operationId;

  /// `parameters`.
  final List<RefOr<Parameter>> parameters;

  /// `requestBody`.
  final RefOr<RequestBody>? requestBody;

  /// `responses` by status code, range (`2XX`) or `default`, in document
  /// order; `x-` keys of the Responses Object are not included.
  final Map<String, RefOr<Response>> responses;

  /// `deprecated`.
  final bool deprecated;

  /// `security`; null when the operation does not set it and inherits the
  /// document's.
  final List<SecurityRequirement>? security;

  /// `servers`.
  final List<Server> servers;
}
