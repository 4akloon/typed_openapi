import '../model/media_type.dart';
import '../model/schema.dart';
import 'ir_context.dart';
import 'json_equality.dart';
import 'ref_follower.dart';
import 'schema_shapes.dart';

/// Decides from the spec, before any type is mapped, whether the event
/// streams of an operation's successes describe their events the same way:
/// by `itemSchema` or by `schema`, each the same type of event. Mapping an
/// inline schema twice would declare it twice, so the answer cannot come
/// from the mapped types.
///
/// Two descriptions are the same when they are one schema or written alike,
/// when they stand for one schema once the wrappers that add nothing (an
/// annotation-only `allOf`, a nullable `anyOf`) are taken off, or, for a
/// `schema`, when they give the same text or scalar type: annotations
/// (`description`, `title`, `example`) never make two types different.
final class EventAgreement {
  /// Creates the check; it reads schemas through [_context].
  const EventAgreement(this._context);

  /// The most wrappers [_unwrapped] takes off a schema: a `$ref` cycle of
  /// wrappers ends there.
  static const _maxWrappers = 16;

  final IrContext _context;

  /// Whether every media type of [medias] (null for none) describes its
  /// events as the first does.
  bool agree(Iterable<MediaType?> medias) {
    final keys = [for (final media in medias) _keyOf(media)];
    return keys.every((key) => _same(keys.first, key));
  }

  /// The way [media] describes its events: where the description is
  /// (`itemSchema` or `schema`) and the schema at the end of its `$ref`s.
  (bool, Schema?)? _keyOf(MediaType? media) {
    if (media?.itemSchema case final item?) {
      return (true, _context.model.resolveSchema(item));
    }
    if (media?.schema case final schema?) {
      return (false, _context.model.resolveSchema(schema));
    }
    return null;
  }

  bool _same((bool, Schema?)? a, (bool, Schema?)? b) {
    final isItemSchema = a?.$1 ?? false;
    if (isItemSchema != (b?.$1 ?? false)) return false;
    final (x, y) = (a?.$2, b?.$2);
    if (_sameSchema(x, y)) return true;
    final (plainX, plainY) = (_unwrapped(x), _unwrapped(y));
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
    return x != null && y != null && JsonEquality.equals(x.$1, y.$1);
  }

  /// [schema] without the wrappers that add nothing to the one schema they
  /// stand for, followed through `$ref`s.
  Schema? _unwrapped(Schema? schema) {
    final refs = RefFollower.of(_context.model);
    var current = schema;
    for (var i = 0; i < _maxWrappers; i++) {
      if (current is! SchemaObject) return current;
      final single = SchemaShapes.singleOf(current, refs: refs);
      if (single == null) return current;
      current = _context.model.resolveSchema(single);
    }
    return current;
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
    final types = [for (final type in schema.types) type.name]..sort();
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
