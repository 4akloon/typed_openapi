import '../model/media_type_name.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'part_media_type.dart';
import 'schema_mapper.dart';

/// Builds the parts of a multipart body (R10.4) whose schema is an object:
/// a part per property, each mapped as a request type.
final class PartsBuilder {
  /// Creates the builder; it maps types with [_mapper].
  const PartsBuilder(this._context, this._mapper);

  static const _names = DartNames();

  final IrContext _context;
  final SchemaMapper _mapper;

  PartMediaType get _mediaTypes => PartMediaType(_context);

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
          _part(scope, media, resolved, wire, property, prefix),
    ];
  }

  /// The part [wire]: its media type is one concrete type ([PartMediaType]),
  /// and an object that cannot be sent as JSON is text the caller supplies.
  PartIr _part(
    NameScope scope,
    MediaType media,
    SchemaObject parent,
    String wire,
    Schema property,
    String prefix,
  ) {
    final name = _claimName(scope, wire, property.location);
    final isRequired = parent.required.contains(wire);
    final encoding = media.encoding[wire];
    final declared = encoding?.contentType;
    final at = encoding?.location.child('contentType');
    String? chosen(PartPayload payload) => at == null
        ? null
        : _mediaTypes.choose(declared, payload, wire: wire, at: at);
    final objectType = _isObjectLike(property) ? chosen(.object) : null;
    final DartType type;
    final String? contentType;
    if (objectType != null && !MediaTypeName(objectType).isJson) {
      type = _textInput(property, isRequired);
      contentType = objectType;
    } else {
      type = _partType(property, prefix, wire, parent);
      contentType = objectType ?? chosen(_isFile(type) ? .file : .text);
    }
    return PartIr(
      name: name,
      wireName: wire,
      type: type,
      location: property.location,
      required: isRequired,
      contentType: contentType,
      description: _description(property),
    );
  }

  /// The text of an object (or of each item of an array of objects) that
  /// is sent in a format other than JSON.
  DartType _textInput(Schema property, bool isRequired) {
    const text = CoreType(.string);
    final isArray = switch (_context.model.resolveSchema(property)) {
      SchemaObject(:final types) => types.contains(SchemaType.array),
      _ => false,
    };
    final type = isArray ? const ListType(text) : text;
    return isRequired ? type : type.withNullable(true);
  }

  /// Whether a value of [property] is written as a JSON object, or is a list
  /// of them.
  bool _isObjectLike(Schema property) {
    final schema = _context.model.resolveSchema(property);
    if (schema is! SchemaObject) return false;
    final items = schema.items;
    if (schema.types.contains(SchemaType.array) && items != null) {
      return _isObjectLike(items);
    }
    return schema.types.contains(SchemaType.object) ||
        schema.properties.isNotEmpty ||
        schema.additionalProperties != null ||
        schema.allOf.isNotEmpty ||
        schema.oneOf.isNotEmpty ||
        schema.anyOf.isNotEmpty;
  }

  static bool _isFile(DartType type) => switch (type) {
    CoreType(kind: .binary) => true,
    ListType(item: CoreType(kind: .binary)) => true,
    _ => false,
  };

  /// The field name of the part [wire]: as an argument is named, with the
  /// same reports (TOA550, TOA551, TOA552, TOA559); a part cannot be named by
  /// an override, so the fix is at the source.
  String _claimName(NameScope scope, String wire, SpecLocation at) {
    final automatic = _names.camel(wire);
    final candidate = automatic ?? 'part';
    final (name, change) = scope.claim(candidate);
    const fix =
        'Rename the property at the source; the part is still sent under '
        'its own name.';
    if (automatic == null) {
      _context.report(
        .nameUnrepresentable,
        'Part "$wire" has no ASCII letter or digit; the field is named '
        '"$name".',
        at,
        fix: fix,
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Part "$wire" would be the Dart name "$candidate"; the field is '
                  'named "$name".'
            : 'Another part is named "$candidate"; the field of part "$wire" '
                  'is named "$name".',
        at,
        fix: fix,
      );
    }
    if (automatic != null) {
      _context.checkLossyName(wire, name, at, what: 'Part', fix: fix);
    }
    return name;
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
