import 'package:dio/dio.dart';

import 'security.dart';

/// What a request is: the operation of the spec it calls.
///
/// The request sender puts it into `RequestOptions.extra` under
/// [extraKey], so interceptors can tell operations apart
/// (`OperationInfo.of(options)?.operationId`).
final class OperationInfo {
  /// Describes one operation.
  const OperationInfo({
    required this.operationId,
    required this.method,
    required this.pathTemplate,
    this.tags = const [],
    this.security = const [],
  });

  /// The key of this object in the `extra` map of a request.
  static const String extraKey = 'typed_openapi.operation';

  /// The `operationId` of the spec, or the name the generator gave the
  /// operation.
  final String operationId;

  /// The HTTP method in upper case.
  final String method;

  /// The path as the spec writes it, such as `/pets/{petId}`.
  final String pathTemplate;

  /// The tags of the operation in spec order.
  final List<String> tags;

  /// The security requirements of the operation (its own `security`, else
  /// the document's): any one of the alternatives is enough, and every
  /// scheme of an alternative is needed. An empty alternative makes
  /// security optional; no alternatives mean no security. The client only
  /// describes them: interceptors add the credentials.
  final List<List<SecurityUse>> security;

  /// The operation of a request, or `null` for a request a generated
  /// client did not send.
  static OperationInfo? of(RequestOptions options) =>
      switch (options.extra[extraKey]) {
        final OperationInfo info => info,
        _ => null,
      };

  @override
  String toString() => '$method $pathTemplate ($operationId)';
}
