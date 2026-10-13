import '../model/media_type.dart';
import '../model/schema.dart';
import 'ir_context.dart';
import 'json_equality.dart';
import 'schema_essence.dart';
import 'schema_unwrapper.dart';

/// Decides from the spec, before any type is mapped, whether the event
/// streams of an operation's successes describe their events the same way:
/// by `itemSchema` or by `schema`, each the same type of event. Mapping an
/// inline schema twice would declare it twice, so the answer cannot come
/// from the mapped types.
///
/// Two descriptions are the same when they are one schema or written alike
/// (`SchemaEssence`: annotations at any depth, and the spelling of
/// nullable, never make two types different), when they stand for one
/// schema once the wrappers that add nothing (an annotation-only `allOf`, a
/// nullable `anyOf`) are taken off, or, for a `schema`, when they give the
/// same text or scalar type.
final class EventAgreement {
  /// Creates the check; it reads schemas through [_context].
  EventAgreement(this._context) : _unwrapper = SchemaUnwrapper(_context.model);

  final IrContext _context;
  final SchemaUnwrapper _unwrapper;

  /// Whether every media type of [medias] (null for none) describes its
  /// events as the first does.
  bool agree(Iterable<MediaType?> medias) {
    final keys = [for (final media in medias) _keyOf(media)];
    return keys.every((key) => _same(keys.first, key));
  }

  /// The way [media] describes its events: where the description is
  /// (`itemSchema` or `schema`) and the schema at the end of its `$ref`s.
  _Description? _keyOf(MediaType? media) {
    if (media?.itemSchema case final item?) {
      return _Description(
        isItemSchema: true,
        schema: _context.model.resolveSchema(item),
      );
    }
    if (media?.schema case final schema?) {
      return _Description(
        isItemSchema: false,
        schema: _context.model.resolveSchema(schema),
      );
    }
    return null;
  }

  bool _same(_Description? a, _Description? b) {
    final isItemSchema = a?.isItemSchema ?? false;
    if (isItemSchema != (b?.isItemSchema ?? false)) return false;
    final (x, y) = (a?.schema, b?.schema);
    if (_sameSchema(x, y)) return true;
    final (plainX, plainY) = (_unwrapper.unwrap(x), _unwrapper.unwrap(y));
    return _sameSchema(plainX, plainY) ||
        (!isItemSchema && _sameScalar(plainX, plainY));
  }

  /// Whether [a] and [b] are one schema, or two in one document that are
  /// written alike.
  bool _sameSchema(Schema? a, Schema? b) {
    if (a == null || b == null) return a == b;
    if (a.location == b.location) return true;
    if (a.location.document != b.location.document) return false;
    final documents = _context.documents;
    final x = documents[a.location.document]?.valueAt(a.location.pointer);
    final y = documents[b.location.document]?.valueAt(b.location.pointer);
    return x != null &&
        y != null &&
        (JsonEquality.equals(x.$1, y.$1) ||
            JsonEquality.equals(
              SchemaEssence.of(x.$1),
              SchemaEssence.of(y.$1),
            ));
  }

  /// Whether [a] and [b] give the same text or scalar: no schema and a
  /// string without a format are both text, and two scalar schemas of the
  /// same types and format are alike whatever they say besides.
  bool _sameScalar(Schema? a, Schema? b) {
    final x = _scalarOf(a);
    final y = _scalarOf(b);
    return x != null && y != null && x == y;
  }

  /// What a scalar [schema] is, as `text`, or `type,type/format`; null when
  /// it is not a scalar.
  String? _scalarOf(Schema? schema) {
    if (schema == null) return 'text';
    if (schema is! SchemaObject || !_isScalar(schema)) return null;
    final types = [
      for (final type in schema.types)
        if (type != SchemaType.nullType) type.name,
    ]..sort();
    final format = schema.format;
    if (format == null && types.length == 1 && types.single == 'string') {
      return 'text';
    }
    return '${types.join(',')}/${format ?? ''}';
  }

  /// Whether [schema] says a type and at most a format: no structure,
  /// values or composition.
  static bool _isScalar(SchemaObject schema) =>
      schema.ref == null &&
      schema.types.isNotEmpty &&
      schema.properties.isEmpty &&
      schema.items == null &&
      schema.prefixItems.isEmpty &&
      schema.additionalProperties == null &&
      schema.enumValues == null &&
      schema.constValue == null &&
      schema.contentSchema == null &&
      schema.contentMediaType == null &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty &&
      schema.not == null;
}

/// How a media type describes its events: by `itemSchema` or by `schema`,
/// and the schema at the end of its `$ref`s.
final class _Description {
  const _Description({required this.isItemSchema, required this.schema});

  final bool isItemSchema;
  final Schema? schema;
}
