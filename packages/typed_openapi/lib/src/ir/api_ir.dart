import '../model/operation.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';

// The parts of the IR that only the API emitter reads (M9): body encodings
// and parts, status types, the root client, servers and security. `ir.dart`
// exports them.

/// How one property of a form or multipart request body is sent: an entry
/// of the media type's `encoding`.
final class EncodingIr {
  /// Creates the encoding of [property].
  const EncodingIr(
    this.property, {
    this.contentType,
    this.style,
    this.explode,
    this.allowReserved = false,
  });

  /// The property name, as in the spec.
  final String property;

  /// `contentType`: the media type of a multipart part, or JSON text for a
  /// form property.
  final String? contentType;

  /// `style` of a form property; null for `form`. A style a query parameter
  /// does not allow is reported (TOA564) and left out.
  final ParameterStyle? style;

  /// `explode`; null for the default of the style.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}

/// A part of a multipart body: a property of its schema.
final class PartIr {
  /// Creates a part.
  const PartIr({
    required this.name,
    required this.wireName,
    required this.type,
    required this.location,
    this.required = false,
    this.contentType,
    this.description,
  });

  /// The Dart name of the field.
  final String name;

  /// The property name, which names the part.
  final String wireName;

  /// The type of the value; `Uint8List` (a binary string) and a list of it
  /// are files.
  final DartType type;

  /// Where the property schema is.
  final SpecLocation location;

  /// Whether the property is required.
  final bool required;

  /// The media type of the part, from the `encoding`.
  final String? contentType;

  /// `description`.
  final String? description;
}

/// A sealed type of an operation: its successes or its errors when the
/// statuses have different bodies (decision 18 of M8).
final class StatusTypeIr {
  /// Creates the type [name] with a variant for each of [cases].
  const StatusTypeIr(this.name, this.cases);

  /// The Dart name of the sealed class.
  final String name;

  /// The variants, in the order of the responses.
  final List<StatusCaseIr> cases;
}

/// A variant of a [StatusTypeIr]: one status.
final class StatusCaseIr {
  /// Creates the variant [name] of [status] with a body of [type].
  const StatusCaseIr(this.status, this.name, this.type);

  /// The status as in the spec: a code, a range such as `4XX`, `default`.
  final String status;

  /// The Dart name of the variant class (`CreatePetErrorNotFound`).
  final String name;

  /// The type of the body; null for a status without a body.
  final DartType? type;
}

/// The root client: a field for each group and the servers (R10.9).
final class RootIr {
  /// Creates the root class [name].
  const RootIr(this.name, {this.servers = const []});

  /// The Dart name of the class (`PetstoreClient`).
  final String name;

  /// The servers of the document, in order.
  final List<ServerIr> servers;
}

/// A server of the document: a constant of the root client, or a static
/// method when the URL has variables.
final class ServerIr {
  /// Creates the server [name] at [url].
  const ServerIr({
    required this.name,
    required this.url,
    required this.location,
    this.description,
    this.variables = const [],
  });

  /// The Dart name of the member.
  final String name;

  /// The URL template, as in the spec.
  final String url;

  /// Where the Server Object is.
  final SpecLocation location;

  /// `description`.
  final String? description;

  /// The variables, in the order of the spec.
  final List<ServerVariableIr> variables;
}

/// A variable of a server URL: an argument of its method.
final class ServerVariableIr {
  /// Creates the variable [wireName], an argument named [name].
  const ServerVariableIr({
    required this.name,
    required this.wireName,
    this.defaultValue,
    this.values = const [],
    this.description,
  });

  /// The Dart name of the argument.
  final String name;

  /// The name in the URL template.
  final String wireName;

  /// `default`; the argument is required without one.
  final String? defaultValue;

  /// `enum`: the values the server takes.
  final List<String> values;

  /// `description`.
  final String? description;
}

/// The `type` of a security scheme, as the runtime names it.
enum SecurityKind {
  /// An API key.
  apiKey,

  /// HTTP authentication.
  http,

  /// Mutual TLS.
  mutualTls,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect.
  openIdConnect,
}

/// A security scheme of `components.securitySchemes` (R10.8).
final class SecuritySchemeIr {
  /// Creates the scheme [name] of [kind].
  const SecuritySchemeIr(
    this.name,
    this.kind, {
    this.parameterName,
    this.placement,
    this.scheme,
    this.bearerFormat,
    this.openIdConnectUrl,
  });

  /// The key in `components.securitySchemes`.
  final String name;

  /// The type of the scheme.
  final SecurityKind kind;

  /// The header, query parameter or cookie name of an API key.
  final String? parameterName;

  /// Where an API key is sent: `query`, `header` or `cookie`.
  final String? placement;

  /// The HTTP authentication scheme, in lower case.
  final String? scheme;

  /// `bearerFormat`.
  final String? bearerFormat;

  /// `openIdConnectUrl`.
  final String? openIdConnectUrl;
}

/// A scheme a security requirement names, with its scopes.
final class SecurityUseIr {
  /// Requires [scheme] with [scopes].
  const SecurityUseIr(this.scheme, this.scopes);

  /// The scheme.
  final SecuritySchemeIr scheme;

  /// The scopes, as in the spec.
  final List<String> scopes;
}
