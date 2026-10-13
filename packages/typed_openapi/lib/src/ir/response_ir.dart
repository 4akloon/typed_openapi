import '../model/spec_node.dart';
import 'body_kind.dart';
import 'dart_type.dart';

/// A response of an operation.
final class ResponseIr {
  /// Creates a response.
  const ResponseIr({
    required this.status,
    required this.kind,
    required this.location,
    this.contentType,
    this.type,
    this.envelopeKey,
    this.description,
    this.sensitive = false,
  });

  /// The status as in the spec: a code, a range such as `4XX`, or
  /// `default`.
  final String status;

  /// How the body is encoded.
  final BodyKind kind;

  /// Where the Response Object is.
  final SpecLocation location;

  /// The media type of the body.
  final String? contentType;

  /// The type of the body; for an envelope (R6.4), the type of its
  /// [envelopeKey] property.
  final DartType? type;

  /// The property of an envelope `{data: T}` the body is unwrapped from.
  final String? envelopeKey;

  /// `description`.
  final String? description;

  /// Whether the body is a secret that must not be printed: `toString` of
  /// the variant of a status type that holds it writes `<redacted>` (see
  /// `FieldIr.sensitive`).
  final bool sensitive;

  /// Whether the status is 2xx.
  bool get isSuccess => status.startsWith('2');

  /// Whether the status is 4xx, 5xx or `default`.
  bool get isError =>
      status.startsWith('4') || status.startsWith('5') || status == 'default';
}
