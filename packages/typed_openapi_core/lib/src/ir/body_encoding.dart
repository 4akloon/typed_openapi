import '../model/operation.dart';
import '../model/schema.dart';
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
  /// has none. A key that names no property of the schema is reported
  /// (TOA659) and left out; a style a query parameter does not allow is
  /// reported (TOA564) and left out; headers cannot be sent and are reported
  /// (TOA656).
  List<EncodingIr> of(MediaType? media, BodyKind kind) {
    if (media == null || kind != .form && kind != .multipart) return const [];
    final properties = _propertyNames(media.schema);
    final result = <EncodingIr>[];
    for (final key in media.encoding.keys.toList()..sort()) {
      final encoding = media.encoding[key];
      if (encoding == null || !_isProperty(key, properties, encoding)) {
        continue;
      }
      _reportHeaders(encoding, key, kind);
      result.add(
        EncodingIr(
          key,
          contentType: encoding.contentType,
          style: _checkedStyle(encoding, key, kind),
          explode: encoding.explode,
          allowReserved: encoding.allowReserved,
        ),
      );
    }
    return result;
  }

  /// Whether [key] names a property; else reports it (TOA659). [properties]
  /// is null when the schema allows any property.
  bool _isProperty(String key, Set<String>? properties, Encoding encoding) {
    if (properties == null || properties.contains(key)) return true;
    _context.report(
      .encodingKeyUnknown,
      'The encoding of "$key" names no property of the body schema, so it '
      'is ignored.',
      encoding.location,
      fix: 'Use the name of a property of the schema, or remove the entry.',
    );
    return false;
  }

  /// The names of the properties of [schema] and of its `$ref` target and
  /// `allOf`, `oneOf` and `anyOf` parts; null when it is unresolved
  /// (reported already), lets any property in (`additionalProperties` other
  /// than `false`) or lists none: a free-form `{type: object}` is open, as
  /// JSON Schema says.
  Set<String>? _propertyNames(Schema? schema) {
    final names = <String>{};
    final seen = <Object>{};
    var isOpen = false;
    var isUnresolved = false;
    void visit(Schema? node) {
      if (node == null) return;
      final resolved = _context.model.resolveSchema(node);
      if (resolved == null) isUnresolved = true;
      if (resolved is! SchemaObject || !seen.add(resolved.location)) return;
      names.addAll(resolved.properties.keys);
      isOpen =
          isOpen ||
          switch (resolved.additionalProperties) {
            null || BooleanSchema(value: false) => false,
            _ => true,
          };
      [...resolved.allOf, ...resolved.oneOf, ...resolved.anyOf].forEach(visit);
    }

    visit(schema);
    return isOpen || isUnresolved || schema != null && names.isEmpty
        ? null
        : names;
  }

  /// The style of a form property as the IR keeps it: what the spec writes
  /// when a query parameter allows it, else null (the default style `form`),
  /// with TOA564; a multipart part has none.
  ParameterStyle? _checkedStyle(
    Encoding encoding,
    String property,
    BodyKind kind,
  ) {
    final allowed = ParameterStyles.allowed[ParameterLocation.query]!;
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

  void _reportHeaders(Encoding encoding, String property, BodyKind kind) {
    if (encoding.headers.isEmpty) return;
    final what = kind == .form ? 'form property' : 'part';
    _context.report(
      .encodingHeadersIgnored,
      'The headers of the $what "$property" are not sent: the client sends '
      '${kind == .form ? 'the value as text' : 'a part with its name, media '
                'type and file name only'}.',
      encoding.location.child('headers'),
      fix: 'Send the headers another way, or remove them at the source.',
    );
  }
}
