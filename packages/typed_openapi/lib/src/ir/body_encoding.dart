import '../model/operation.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'parameter_styles.dart';

/// Reads the `encoding` of a form or multipart request body.
final class BodyEncoding {
  /// Creates the reader; it reports through [_context].
  const BodyEncoding(this._context);

  final IrContext _context;

  /// The `encoding` of a form or multipart body of [kind], by property name;
  /// another kind, or no [media] (an unresolved one is reported already),
  /// has none. A style a query parameter does not allow is reported (TOA564)
  /// and left out; headers of a part cannot be sent and are reported
  /// (TOA656).
  List<EncodingIr> of(MediaType? media, BodyKind kind) {
    if (media == null || kind != .form && kind != .multipart) return const [];
    final allowed = ParameterStyles.allowed[ParameterLocation.query]!;
    return [
      for (final property in media.encoding.keys.toList()..sort())
        if (media.encoding[property] case final encoding?)
          EncodingIr(
            property,
            contentType: encoding.contentType,
            style: _encodingStyle(encoding, property, kind, allowed),
            explode: encoding.explode,
            allowReserved: encoding.allowReserved,
          ),
    ];
  }

  ParameterStyle? _encodingStyle(
    Encoding encoding,
    String property,
    BodyKind kind,
    List<ParameterStyle> allowed,
  ) {
    if (encoding.headers.isNotEmpty) {
      _context.report(
        .encodingHeadersIgnored,
        'The headers of part "$property" are not sent: the client sends a '
        'part with its name, media type and file name only.',
        encoding.location.child('headers'),
        fix: 'Send the headers another way, or remove them at the source.',
      );
    }
    final style = encoding.style;
    if (style == null || kind != .form || allowed.contains(style)) {
      return kind == .form ? style : null;
    }
    _context.report(
      .parameterStyleInvalid,
      'The style "${style.name}" is not allowed for a form property, which '
      'takes ${[for (final s in allowed) '"${s.name}"'].join(', ')}; the '
      'default style "form" is used for "$property".',
      encoding.location.child('style'),
      fix: 'Use one of these styles at the source.',
    );
    return null;
  }
}
