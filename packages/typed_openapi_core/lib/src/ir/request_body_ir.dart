import '../model/spec_node.dart';
import 'api_ir.dart';
import 'body_kind.dart';
import 'dart_type.dart';

/// The request body of an operation.
final class RequestBodyIr {
  /// Creates a request body.
  const RequestBodyIr({
    required this.kind,
    required this.location,
    this.contentType,
    this.type,
    this.required = false,
    this.description,
    this.encoding = const [],
    this.parts,
  });

  /// How the body is encoded.
  final BodyKind kind;

  /// Where the Request Body Object is.
  final SpecLocation location;

  /// The media type the client sends.
  final String? contentType;

  /// The type of the body.
  final DartType? type;

  /// Whether the body is required.
  final bool required;

  /// `description`.
  final String? description;

  /// The `encoding` of the properties of a form or multipart body, by
  /// property name.
  final List<EncodingIr> encoding;

  /// The parts of a multipart body whose schema is an object: the
  /// properties, each a field of a class of its own
  /// (`OperationIr.partsName`) whose files are `FileUpload`s. Null for
  /// other bodies and for a multipart body of another schema, whose [type]
  /// is sent part by part from its JSON (TOA655).
  final List<PartIr>? parts;
}
