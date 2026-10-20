import '../model/parameter.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';

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
