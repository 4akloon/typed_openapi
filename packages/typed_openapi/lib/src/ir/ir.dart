import '../model/operation.dart';
import '../model/spec_node.dart';
import 'api_ir.dart';
import 'dart_type.dart';

export 'api_ir.dart';

/// The semantic IR of one client: what the emitters print, with Dart names
/// and types already chosen.
///
/// Every list is sorted, so the same spec and config give the same IR.
final class ClientIr {
  /// Creates the IR; [declarations] and [groups] are sorted by name.
  ClientIr({
    required List<Declaration> declarations,
    required List<GroupIr> groups,
    this.root = const RootIr('ApiClient'),
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

  /// The root client class.
  final RootIr root;

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
    this.additionalPropertiesName = 'additionalProperties',
    this.additionalSensitive = false,
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

  /// The Dart name of the field that holds [additionalProperties], given in
  /// the scope of the model's fields.
  final String additionalPropertiesName;

  /// Whether the values of `additionalProperties` are secrets: `toString`
  /// does not print them.
  final bool additionalSensitive;
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
    this.constValue,
    this.constraints = const ConstraintsIr(),
    this.sensitive = false,
    this.knownValues = const [],
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

  /// The one value the property can hold, when its schema is a `const` or
  /// an enum with one value written inline (not nullable): the field is a
  /// constant, not a constructor parameter, and [valueType] is the type of
  /// the value.
  final Object? constValue;

  /// The constraints of the property's schema (R6.7), for documentation.
  final ConstraintsIr constraints;

  /// Whether the value is a secret: the property is `writeOnly` or has
  /// `format: password`, also through a `$ref`, the one non-null branch of
  /// a nullable `oneOf`/`anyOf`, or as the items of an array, the values of
  /// a map or a branch of a union. `toString` does not print it.
  final bool sensitive;

  /// The values of the enum branches of the property's schema that a union
  /// left out because another branch has them (TOA455), in order and once
  /// each; the field's doc comment lists them.
  final List<Object?> knownValues;

  /// The type of the field (R6.1): `Patch<T>?` for a tri-state field, the
  /// value type for a required one, and a nullable value type otherwise.
  DartType get type {
    if (triState) {
      return PatchType(valueType.withNullable(false), nullable: true);
    }
    return required ? valueType : valueType.withNullable(true);
  }
}

/// The constraints of a schema (R6.7): the client documents them and
/// checks none.
///
/// OpenAPI 3.0's boolean `exclusiveMinimum` and `exclusiveMaximum` are read
/// into the bound they make exclusive, so 3.0 and 3.1 give the same value.
final class ConstraintsIr {
  /// Creates the constraints; all are optional.
  const ConstraintsIr({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    this.minItems,
    this.maxItems,
    this.uniqueItems = false,
    this.minProperties,
    this.maxProperties,
  });

  /// `minLength`.
  final int? minLength;

  /// `maxLength`.
  final int? maxLength;

  /// `pattern`.
  final String? pattern;

  /// `minimum`, when it is inclusive.
  final num? minimum;

  /// `maximum`, when it is inclusive.
  final num? maximum;

  /// The exclusive lower bound.
  final num? exclusiveMinimum;

  /// The exclusive upper bound.
  final num? exclusiveMaximum;

  /// `multipleOf`.
  final num? multipleOf;

  /// `minItems`.
  final int? minItems;

  /// `maxItems`.
  final int? maxItems;

  /// `uniqueItems`.
  final bool uniqueItems;

  /// `minProperties`.
  final int? minProperties;

  /// `maxProperties`.
  final int? maxProperties;

  /// Whether no constraint is set.
  bool get isEmpty =>
      minLength == null &&
      maxLength == null &&
      pattern == null &&
      minimum == null &&
      maximum == null &&
      exclusiveMinimum == null &&
      exclusiveMaximum == null &&
      multipleOf == null &&
      minItems == null &&
      maxItems == null &&
      !uniqueItems &&
      minProperties == null &&
      maxProperties == null;
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
    String? knownName,
    String? unknownName,
    super.description,
    super.deprecated,
  }) : _knownName = knownName,
       _unknownName = unknownName;

  /// The JSON type of the values.
  final EnumKind kind;

  /// The values, in the order of the spec.
  final List<EnumValueIr> values;

  /// Whether a `switch` must name every value (research §7.8).
  final bool exhaustive;

  final String? _knownName;
  final String? _unknownName;

  /// The Dart enum of the values the spec lists (`StatusKnown`), named in
  /// the library scope after the declarations and the groups.
  String get knownName => _knownName ?? '${name}Known';

  /// The class of a value the spec does not list (`StatusUnknown`).
  String get unknownName => _unknownName ?? '${name}Unknown';
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

/// The JSON type of a value: what a union without a discriminator tells
/// its variants apart by (R9.3).
enum JsonKind {
  /// A string.
  string,

  /// A whole number.
  integer,

  /// Any number.
  number,

  /// `true` or `false`.
  boolean,

  /// An array.
  array,

  /// An object.
  object,
}

/// How a union's `fromJson` picks a variant (R9).
enum UnionDispatch {
  /// By the value of the discriminator property and its mapping.
  discriminator,

  /// By the JSON type of the value (R9.3): a variant of each JSON type that
  /// one variant alone has, and one variant of any JSON value
  /// ([UnionVariantIr.jsonKinds]) for the types several variants share.
  jsonType,

  /// By trying the variants (`union: structural`, R9.2): a `oneOf` takes
  /// the one variant that decodes, an `anyOf` the first.
  structural,
}

/// A `oneOf` or `anyOf` with more than one variant besides `null` (R9).
final class UnionDecl extends Declaration {
  /// Creates a union.
  const UnionDecl({
    required super.id,
    required super.name,
    required this.kind,
    required this.variants,
    this.dispatch = .discriminator,
    this.discriminator,
    this.defaultVariant,
    this.exhaustive = true,
    this.unknownSensitive = false,
    String? unknownName,
    super.description,
    super.deprecated,
  }) : _unknownName = unknownName;

  /// `oneOf` or `anyOf`.
  final UnionKind kind;

  /// How `fromJson` picks a variant.
  final UnionDispatch dispatch;

  final String? _unknownName;

  /// The class of a value no variant takes (`PetUnknown`), named in the
  /// library scope after the declarations and the groups.
  String get unknownName => _unknownName ?? '${name}Unknown';

  /// The variants, in the order of the spec.
  final List<UnionVariantIr> variants;

  /// The discriminator property name, if any.
  final String? discriminator;

  /// The variant for a discriminator value no variant has: OpenAPI 3.2
  /// `defaultMapping`.
  final DartType? defaultVariant;

  /// Whether a `switch` must name every variant (research §7.8).
  final bool exhaustive;

  /// Whether a value no variant takes could still hold a secret: a variant
  /// has a secret anywhere in its schema, so `toString` of the unknown
  /// variant, which keeps the raw JSON, does not print it.
  final bool unknownSensitive;
}

/// A variant of a union.
final class UnionVariantIr {
  /// Creates a variant.
  const UnionVariantIr(
    this.type, {
    this.discriminatorValues = const [],
    this.name = '',
    this.jsonKinds = const [],
    this.sensitive = false,
  });

  /// The type of the variant.
  final DartType type;

  /// The class that wraps a value of [type] (`PetCat`), named in the
  /// library scope after the declarations and the groups.
  final String name;

  /// For the variant of any JSON value of a union dispatched by JSON type:
  /// the JSON types it takes, those several variants share (R9.2). Empty
  /// for every other variant.
  final List<JsonKind> jsonKinds;

  /// The discriminator values that select this variant, sorted.
  final List<String> discriminatorValues;

  /// Whether the value of the variant is a secret: `toString` of its class
  /// does not print it (see [FieldIr.sensitive]).
  final bool sensitive;
}

/// An API class: the operations of a tag, a path segment or the whole spec
/// (R5.3).
final class GroupIr {
  /// Creates a group; [operations] are sorted by name.
  GroupIr(this.name, List<OperationIr> operations, {this.field = 'api'})
    : operations = List.unmodifiable(
        operations.toList()..sort((a, b) => a.name.compareTo(b.name)),
      );

  /// The Dart name of the class.
  final String name;

  /// The name of the group's field in the root client (`pets` for
  /// `PetsApi`).
  final String field;

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
    this.security = const [],
    this.successType,
    this.errorType,
    this.partsName,
  });

  /// This operation with the names of the types the API emitter declares
  /// for it, given after the declarations.
  OperationIr withTypes({
    StatusTypeIr? successType,
    StatusTypeIr? errorType,
    String? partsName,
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

  /// The key of the operation in the overrides file: its `operationId`,
  /// or `METHOD /path`.
  String get overrideKey => operationId ?? '$method $path';

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
    this.defaultValue,
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

  /// `default` of the parameter's schema, as a one-element record: the
  /// value the server uses when the argument is not sent. It is documented,
  /// not sent.
  final (Object?,)? defaultValue;
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
  /// ([OperationIr.partsName]) whose files are `FileUpload`s. Null for
  /// other bodies and for a multipart body of another schema, whose [type]
  /// is sent part by part from its JSON (TOA655).
  final List<PartIr>? parts;
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

  /// The documented error statuses; empty means every 4xx and 5xx one.
  final List<String> statuses;
}

/// Errors with different body types: `E` is a sealed type by status.
final class ErrorsByStatus extends ErrorsIr {
  /// Creates the errors.
  const ErrorsByStatus(this.cases);

  /// The body type of each status; null for a body-less status.
  final List<(String, DartType?)> cases;
}
