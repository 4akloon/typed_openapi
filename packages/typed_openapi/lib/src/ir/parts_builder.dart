import '../model/operation.dart';
import '../model/schema.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'schema_mapper.dart';

/// Builds the parts of a multipart body (R10.4) whose schema is an object:
/// a part per property, each mapped as a request type.
final class PartsBuilder {
  /// Creates the builder; it maps types with [_mapper].
  const PartsBuilder(this._context, this._mapper);

  static const _names = DartNames();

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The parts of a multipart body whose [media] has an object schema with
  /// properties, each mapped as a request type; read-only properties are
  /// left out. Another schema is reported (TOA655) and gives null, as does
  /// no [media] (an unresolved one is reported already) or no schema.
  List<PartIr>? of(MediaType? media, String prefix) {
    final schema = media?.schema;
    if (media == null || schema == null) return null;
    final resolved = _context.model.resolveSchema(schema);
    if (resolved is! SchemaObject || !_hasParts(resolved)) {
      _reportNotObject(schema);
      return null;
    }
    final scope = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.objectMembers,
        ...DartNames.lowercaseTypes,
        ...DartNames.helperFunctions,
        'toParts',
      },
      reservedSuffix: '_',
    );
    return [
      for (final MapEntry(key: wire, value: property)
          in resolved.properties.entries)
        if (!_isReadOnly(property))
          PartIr(
            name: scope.claim(_names.camel(wire) ?? 'part').$1,
            wireName: wire,
            type: _partType(property, prefix, wire, resolved),
            location: property.location,
            required: resolved.required.contains(wire),
            contentType: media.encoding[wire]?.contentType,
            description: _description(property),
          ),
    ];
  }

  void _reportNotObject(Schema schema) {
    _context.report(
      .multipartNotObject,
      'The multipart body is not an object with properties, so it has no '
      'class of parts: each property of its JSON is sent as a part, and '
      'binary strings as base64 text.',
      schema.location,
      fix:
          'Describe the body as an object with a property for each part at '
          'the source.',
    );
  }

  /// Whether [schema] is a plain object with properties.
  static bool _hasParts(SchemaObject schema) =>
      schema.properties.isNotEmpty &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty &&
      schema.types.every((t) => t == .object || t == .nullType);

  DartType _partType(
    Schema property,
    String prefix,
    String wire,
    SchemaObject parent,
  ) {
    final type = _mapper.typeOf(
      property,
      NameHint(prefix, 'Request${_names.pascal(wire) ?? ''}'),
      direction: .request,
    );
    return parent.required.contains(wire) ? type : type.withNullable(true);
  }

  String? _description(Schema property) =>
      switch (_context.model.resolveSchema(property)) {
        final SchemaObject target => target.description,
        _ => null,
      };

  bool _isReadOnly(Schema property) =>
      switch (_context.model.resolveSchema(property)) {
        final SchemaObject target => target.readOnly,
        _ => false,
      };
}
