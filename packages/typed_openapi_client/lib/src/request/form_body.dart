import 'dart:convert';

import '../params/parameters.dart';

/// How one property of an `application/x-www-form-urlencoded` body is
/// written: the `encoding` of the spec's media type for that property.
final class FormEncoding {
  /// Creates the encoding; OAS defaults are `form` with explode.
  const FormEncoding({
    this.style = .form,
    this.explode,
    this.allowReserved = false,
    this.json = false,
  });

  /// The serialization style, as for a query parameter.
  final QueryStyle style;

  /// Whether lists and objects are exploded; null for the default of the
  /// style.
  final bool? explode;

  /// Whether reserved characters are sent without percent-encoding.
  final bool allowReserved;

  /// Whether the value is sent as JSON text (`contentType:
  /// application/json` in the encoding).
  final bool json;
}

/// An `application/x-www-form-urlencoded` body: the properties of a JSON
/// object, each written like a query parameter (OAS 3 `encoding`).
///
/// A property without an [encoding] entry uses the `form` style with
/// explode; `null` values are not sent. Values nested deeper than the style
/// allows (an object inside an object for `form`) make [encode] throw
/// [ArgumentError], as query parameters do.
final class FormBody {
  /// Creates the body of [json], which must be a JSON object or `null`.
  const FormBody(this.json, [this.encoding = const {}]);

  /// The body as JSON (`toJson()` of the model).
  final Object? json;

  /// The encoding of properties by name.
  final Map<String, FormEncoding> encoding;

  /// The body text: `name=value` pairs joined by `&`.
  ///
  /// Throws [ArgumentError] when [json] is not an object.
  String encode() {
    final object = switch (json) {
      null => const <String, Object?>{},
      final Map<String, Object?> object => object,
      final other => throw ArgumentError.value(
        other,
        'json',
        'A form body must be a JSON object',
      ),
    };
    return [
      for (final MapEntry(:key, :value) in object.entries)
        _field(key, value, encoding[key] ?? const FormEncoding()),
    ].where((pair) => pair.isNotEmpty).join('&');
  }

  static String _field(String name, Object? value, FormEncoding encoding) =>
      QueryParameter(
        name,
        encoding.json && value != null ? jsonEncode(value) : value,
        style: encoding.style,
        explode: encoding.explode,
        allowReserved: encoding.allowReserved,
      ).encode();
}
