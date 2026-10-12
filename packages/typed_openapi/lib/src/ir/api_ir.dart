import '../model/operation.dart';

// The parts of the IR that only the API emitter reads (M9). `ir.dart`
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
