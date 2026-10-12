import 'parameter_value.dart';
import 'percent_encoder.dart';

/// The `style` of a path parameter.
enum PathStyle {
  /// `blue`, `blue,black`, `R,100,G,200` (explode: `R=100,G=200`).
  simple,

  /// `.blue`, `.blue,black` (explode: `.blue.black`).
  label,

  /// `;color=blue`, `;color=blue,black` (explode: `;color=blue;color=black`).
  matrix,
}

/// The `style` of a query parameter.
enum QueryStyle {
  /// `color=blue`, `color=blue&color=black` (no explode: `color=blue,black`).
  form,

  /// Arrays joined by spaces: `color=blue%20black`.
  spaceDelimited,

  /// Arrays joined by pipes: `color=blue%7Cblack`.
  pipeDelimited,

  /// Objects as `color%5BR%5D=100&color%5BG%5D=200` (`color[R]=100`).
  deepObject,
}

/// A path parameter: its value replaces `{name}` in the path template.
///
/// Values are the JSON form of the parameter (`toJson` applied): a scalar, a
/// list or a string-keyed map. Every character but the unreserved ones is
/// percent-encoded, so a value cannot add path segments. A value that would
/// remove or climb a path segment is rejected, see [encode].
final class PathParameter {
  /// Creates a path parameter; OAS defaults are `simple` without explode.
  const PathParameter(
    this.name,
    this.value, {
    this.style = .simple,
    this.explode = false,
  });

  /// The name in the path template.
  final String name;

  /// The JSON form of the value.
  final Object? value;

  /// The serialization style.
  final PathStyle style;

  /// Whether lists and objects are exploded.
  final bool explode;

  /// The text that replaces `{name}`.
  ///
  /// Throws [ArgumentError] when the value would change the request path,
  /// because a client drops an empty path segment (`//`) and normalizes `.`
  /// and `..` away, and percent-encoding does not help:
  ///
  /// - the expansion is empty (`''`, `null`, an empty list or map, or a list
  ///   of one empty string with the `simple` style);
  /// - the expansion is a dot segment, `.` or `..` (the `label` style of
  ///   `''`, or of two empty strings with explode);
  /// - a scalar, an item, a key or a property value is exactly `.` or `..`.
  ///
  /// Neighbours are valid: `.a`, `a..b`, `...` (not a dot segment), `.a.b`
  /// (`label` of `a` and `b`) and `;id` (`matrix` of `''`).
  String encode() {
    final value = ParameterValue.of(this.value, kind: style.name);
    final expansion = _expand(value);
    final texts = switch (value) {
      UndefinedValue() => const <String>[],
      ScalarValue(:final text) => [text],
      ListValue(:final items) => items,
      ObjectValue(:final pairs) => [
        for (final (key, text) in pairs) ...[key, text],
      ],
    };
    final dots = texts.where((text) => text == '.' || text == '..').firstOrNull;
    final problem = switch (expansion) {
      _ when dots != null => 'cannot be a dot segment ("$dots")',
      '' => 'cannot be empty',
      _ when _dotSegment.hasMatch(expansion) =>
        'cannot be a dot segment ("$expansion")',
      _ => null,
    };
    if (problem != null) {
      throw ArgumentError.value(
        this.value,
        name,
        'A path parameter value $problem: it would change the request path',
      );
    }
    return expansion;
  }

  static final RegExp _dotSegment = RegExp(r'^\.{1,2}$');

  String _expand(ParameterValue value) => switch (style) {
    .simple => value.expand(
      name,
      encoder: .unreserved,
      explode: explode,
      named: false,
    ),
    .label => value.expand(
      name,
      encoder: .unreserved,
      explode: explode,
      named: false,
      first: '.',
      separator: '.',
    ),
    .matrix => value.expand(
      name,
      encoder: .unreserved,
      explode: explode,
      named: true,
      first: ';',
      separator: ';',
    ),
  };
}

/// A query parameter.
///
/// Values are the JSON form of the parameter, as for [PathParameter];
/// undefined values are not sent. Names and values are percent-encoded;
/// [allowReserved] keeps the reserved characters that are safe in a query.
final class QueryParameter {
  /// Creates a query parameter. OAS defaults: `form`; explode for `form`
  /// only.
  const QueryParameter(
    this.name,
    this.value, {
    this.style = .form,
    bool? explode,
    this.allowReserved = false,
  }) : explode = explode ?? style == .form;

  /// The parameter name.
  final String name;

  /// The JSON form of the value.
  final Object? value;

  /// The serialization style.
  final QueryStyle style;

  /// Whether lists and objects are exploded.
  final bool explode;

  /// Whether reserved characters are sent without percent-encoding.
  final bool allowReserved;

  /// The `name=value` pairs joined by `&`, or `''` when the value is
  /// undefined.
  String encode() {
    final value = ParameterValue.of(this.value, kind: style.name);
    final PercentEncoder encoder = allowReserved ? .reserved : .unreserved;
    if (style == .deepObject) return _deepObject(value, encoder);
    return value.expand(
      name,
      encoder: encoder,
      explode: explode,
      named: true,
      separator: '&',
      delimiter: switch (style) {
        .spaceDelimited => '%20',
        .pipeDelimited => '%7C',
        _ => ',',
      },
      ifEmpty: '=',
    );
  }

  String _deepObject(ParameterValue value, PercentEncoder encoder) {
    final key = PercentEncoder.unreserved.encode(name);
    return switch (value) {
      UndefinedValue() => '',
      ObjectValue(:final pairs) => [
        for (final (property, text) in pairs)
          '$key%5B${PercentEncoder.unreserved.encode(property)}%5D='
              '${encoder.encode(text)}',
      ].join('&'),
      _ => throw ArgumentError.value(
        this.value,
        name,
        'deepObject serializes objects only',
      ),
    };
  }
}

/// A header parameter (`simple` style).
///
/// Values are the JSON form of the parameter, as for [PathParameter]. They
/// are not percent-encoded, except control characters and non-ASCII, which
/// a header value cannot carry.
final class HeaderParameter {
  /// Creates a header parameter; the OAS default is no explode.
  const HeaderParameter(this.name, this.value, {this.explode = false});

  /// The header name.
  final String name;

  /// The JSON form of the value.
  final Object? value;

  /// Whether objects are written as `R=100,G=200`.
  final bool explode;

  /// The header value, or `null` when the value is undefined.
  String? encode() => switch (ParameterValue.of(value, kind: 'header')) {
    UndefinedValue() => null,
    final defined => defined.expand(
      name,
      encoder: .header,
      explode: explode,
      named: false,
    ),
  };
}

/// A cookie parameter: one or more `name=value` pairs of the `Cookie`
/// header.
///
/// Values are the JSON form of the parameter, as for [PathParameter], and
/// are percent-encoded. Exploded lists and objects give one pair per item,
/// joined by `; `.
final class CookieParameter {
  /// Creates a cookie parameter; the OAS default is explode.
  const CookieParameter(this.name, this.value, {this.explode = true});

  /// The cookie name.
  final String name;

  /// The JSON form of the value.
  final Object? value;

  /// Whether lists and objects give one pair per item.
  final bool explode;

  /// The pairs joined by `; `, or `null` when the value is undefined.
  String? encode() => switch (ParameterValue.of(value, kind: 'cookie')) {
    UndefinedValue() => null,
    final defined => defined.expand(
      name,
      encoder: .unreserved,
      explode: explode,
      named: true,
      separator: '; ',
      ifEmpty: '=',
    ),
  };
}
