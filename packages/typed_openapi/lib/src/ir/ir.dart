import '../model/operation.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';

/// The semantic IR of one client: what the emitters print, with Dart names
/// and types already chosen.
///
/// Every list is sorted, so the same spec and config give the same IR.
final class ClientIr {
  /// Creates the IR; [declarations] and [groups] are sorted by name.
  ClientIr({
    required List<Declaration> declarations,
    required List<GroupIr> groups,
  }) : declarations = List.unmodifiable(
         declarations.toList()..sort((a, b) => a.name.compareTo(b.name)),
       ),
       groups = List.unmodifiable(
         groups.toList()..sort((a, b) => a.name.compareTo(b.name)),
       );

  /// The models, enums and unions, by name.
  final List<Declaration> declarations;

  /// The API classes, by name.
  final List<GroupIr> groups;

  late final Map<DeclId, Declaration> _byId = {
    for (final declaration in declarations) declaration.id: declaration,
  };

  /// The declaration [id] names, if it is generated.
  Declaration? operator [](DeclId id) => _byId[id];

  /// The Dart name of the declaration [id]; `?` when it is not generated.
  String nameOf(DeclId id) => _byId[id]?.name ?? '?';
}

/// A generated model, enum or union.
sealed class Declaration {
  /// Creates a declaration.
  const Declaration({
    required this.id,
    required this.name,
    this.description,
    this.deprecated = false,
  });

  /// The identity of the declaration.
  final DeclId id;

  /// The Dart name of the type.
  final String name;

  /// `description` of the schema.
  final String? description;

  /// `deprecated` of the schema.
  final bool deprecated;

  /// Where the schema is.
  SpecLocation get location => id.location;
}

/// Where a model is used.
enum ModelDirection {
  /// In requests and responses.
  both,

  /// In responses only: `writeOnly` properties are left out.
  response,

  /// In requests only: `readOnly` properties are left out.
  request,
}

/// A class with fields: an object schema, or the flat merge of an `allOf`.
final class ModelDecl extends Declaration {
  /// Creates a model.
  const ModelDecl({
    required super.id,
    required super.name,
    required this.fields,
    this.direction = .both,
    this.additionalProperties,
    super.description,
    super.deprecated,
  });

  /// The fields, in the order of the schema's properties.
  final List<FieldIr> fields;

  /// Where the model is used.
  final ModelDirection direction;

  /// The type of the values of `additionalProperties`, when the schema
  /// allows other keys with a schema.
  final DartType? additionalProperties;
}

/// A field of a model.
final class FieldIr {
  /// Creates a field.
  const FieldIr({
    required this.name,
    required this.jsonKey,
    required this.valueType,
    required this.location,
    this.required = false,
    this.triState = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.defaultValue,
    this.description,
    this.deprecated = false,
  });

  /// The Dart name.
  final String name;

  /// The property name in JSON, as in the spec.
  final String jsonKey;

  /// The type of a value; nullable when the schema allows `null`.
  final DartType valueType;

  /// Where the property schema is.
  final SpecLocation location;

  /// Whether the property is in the schema's `required`.
  final bool required;

  /// Whether the field tells "absent" from `null` (R7).
  final bool triState;

  /// `readOnly`.
  final bool readOnly;

  /// `writeOnly`.
  final bool writeOnly;

  /// `default`, as a one-element record.
  final (Object?,)? defaultValue;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;

  /// The type of the field (R6.1): `Patch<T>?` for a tri-state field, the
  /// value type for a required one, and a nullable value type otherwise.
  DartType get type {
    if (triState) {
      return PatchType(valueType.withNullable(false), nullable: true);
    }
    return required ? valueType : valueType.withNullable(true);
  }
}

/// The JSON type of an enum's values.
enum EnumKind {
  /// Strings.
  string,

  /// Whole numbers.
  integer,

  /// Numbers.
  number,

  /// Booleans.
  boolean,
}

/// An enum; unknown values are kept when decoding (R8.1).
final class EnumDecl extends Declaration {
  /// Creates an enum.
  const EnumDecl({
    required super.id,
    required super.name,
    required this.kind,
    required this.values,
    this.exhaustive = true,
    super.description,
    super.deprecated,
  });

  /// The JSON type of the values.
  final EnumKind kind;

  /// The values, in the order of the spec.
  final List<EnumValueIr> values;

  /// Whether a `switch` must name every value (research §7.8).
  final bool exhaustive;
}

/// A value of an enum.
final class EnumValueIr {
  /// Creates a value.
  const EnumValueIr(this.name, this.value, {this.description});

  /// The Dart name.
  final String name;

  /// The value in JSON.
  final Object value;

  /// `x-enum-descriptions` for the value.
  final String? description;
}

/// Whether a union is `oneOf` or `anyOf`.
enum UnionKind {
  /// Exactly one variant matches.
  oneOf,

  /// At least one variant matches.
  anyOf,
}

/// A `oneOf` or `anyOf` with more than one variant besides `null` (R9).
final class UnionDecl extends Declaration {
  /// Creates a union.
  const UnionDecl({
    required super.id,
    required super.name,
    required this.kind,
    required this.variants,
    this.discriminator,
    this.defaultVariant,
    this.exhaustive = true,
    super.description,
    super.deprecated,
  });

  /// `oneOf` or `anyOf`.
  final UnionKind kind;

  /// The variants, in the order of the spec.
  final List<UnionVariantIr> variants;

  /// The discriminator property name, if any.
  final String? discriminator;

  /// The variant for a discriminator value no variant has: OpenAPI 3.2
  /// `defaultMapping`.
  final DartType? defaultVariant;

  /// Whether a `switch` must name every variant (research §7.8).
  final bool exhaustive;
}

/// A variant of a union.
final class UnionVariantIr {
  /// Creates a variant.
  const UnionVariantIr(this.type, {this.discriminatorValues = const []});

  /// The type of the variant.
  final DartType type;

  /// The discriminator values that select this variant, sorted.
  final List<String> discriminatorValues;
}

/// An API class: the operations of a tag, a path segment or the whole spec
/// (R5.3).
final class GroupIr {
  /// Creates a group; [operations] are sorted by name.
  GroupIr(this.name, List<OperationIr> operations)
    : operations = List.unmodifiable(
        operations.toList()..sort((a, b) => a.name.compareTo(b.name)),
      );

  /// The Dart name of the class.
  final String name;

  /// The operations, by method name.
  final List<OperationIr> operations;
}

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
  });

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

  /// The responses with a 2xx status.
  List<ResponseIr> get successes => [
    for (final response in responses)
      if (response.isSuccess) response,
  ];
}

/// A parameter of an operation.
final class ParameterIr {
  /// Creates a parameter.
  const ParameterIr({
    required this.name,
    required this.wireName,
    required this.placement,
    required this.type,
    required this.location,
    this.required = false,
    this.style,
    this.explode,
    this.allowReserved = false,
    this.contentType,
    this.description,
    this.deprecated = false,
  });

  /// The Dart name of the argument.
  final String name;

  /// The name in the request, as in the spec.
  final String wireName;

  /// Where the parameter is sent.
  final ParameterLocation placement;

  /// The type of the argument; nullable unless [required].
  final DartType type;

  /// Where the Parameter Object is.
  final SpecLocation location;

  /// Whether the argument is required; path parameters always are.
  final bool required;

  /// `style`; null for the default of [placement].
  final ParameterStyle? style;

  /// `explode`; null for the default of the style.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;

  /// The media type of `content`, when the parameter has one instead of a
  /// schema.
  final String? contentType;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;
}

/// How a body is encoded.
enum BodyKind {
  /// JSON (`application/json` or `+json`).
  json,

  /// `application/x-www-form-urlencoded`.
  form,

  /// `multipart/form-data`.
  multipart,

  /// Text (`text/*` except `text/event-stream`).
  text,

  /// Server-sent events (`text/event-stream`).
  eventStream,

  /// Any other media type: raw bytes.
  bytes,

  /// No content.
  none,
}

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
}

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

  /// Whether the status is 2xx.
  bool get isSuccess => status.startsWith('2');

  /// Whether the status is 4xx, 5xx or `default`.
  bool get isError =>
      status.startsWith('4') || status.startsWith('5') || status == 'default';
}

/// The documented errors of an operation (R11.4).
sealed class ErrorsIr {
  /// Creates the errors.
  const ErrorsIr();
}

/// No documented error: `E` is `Never`.
final class NoErrors extends ErrorsIr {
  /// Creates the value.
  const NoErrors();
}

/// Every documented error has the same body type, which is `E`.
final class SingleError extends ErrorsIr {
  /// Creates the errors.
  const SingleError(this.type, this.statuses);

  /// The body type of every error.
  final DartType type;

  /// The documented error statuses.
  final List<String> statuses;
}

/// Errors with different body types: `E` is a sealed type by status.
final class ErrorsByStatus extends ErrorsIr {
  /// Creates the errors.
  const ErrorsByStatus(this.cases);

  /// The body type of each status; null for a body-less status.
  final List<(String, DartType?)> cases;
}
