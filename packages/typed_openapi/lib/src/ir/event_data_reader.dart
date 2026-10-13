import '../model/media_type_name.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir_context.dart';
import 'ref_follower.dart';
import 'schema_mapper.dart';
import 'schema_shapes.dart';

/// Reads what the data of one event is (decision 1 of M10): JSON in a
/// `contentSchema`, a string as text, or neither (TOA666).
final class EventDataReader {
  /// Creates the reader; it maps types with [_mapper].
  const EventDataReader(this._context, this._mapper);

  /// The most wrappers [_plain] takes off a schema: a `$ref` cycle of
  /// wrappers ends there.
  static const _maxWrappers = 16;

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The type of the event data [data] describes, as a one-element record:
  /// JSON in a `contentSchema` with a JSON `contentMediaType`, or null for
  /// text (a string, also one with a `contentMediaType` that is not JSON);
  /// null itself when [data] says neither.
  (DartType?,)? read(Schema? data, NameHint hint) {
    final schema = data == null ? null : _plain(data);
    if (schema is! SchemaObject) return null;
    final contentSchema = schema.contentSchema;
    final mediaType = schema.contentMediaType;
    final isJson = mediaType != null && MediaTypeName(mediaType).isJson;
    if (contentSchema != null && isJson) {
      return (json(contentSchema, hint),);
    }
    if (contentSchema == null &&
        !isJson &&
        (schema.types.isEmpty || schema.types.contains(SchemaType.string))) {
      return (null,);
    }
    return null;
  }

  /// The `data` property of [item]: its own, or the one a part of its
  /// `allOf` has, at any depth (a `$ref` cycle is read once).
  Schema? dataOf(SchemaObject item) {
    final seen = <SpecLocation>{};
    Schema? search(SchemaObject object) {
      if (!seen.add(object.location)) return null;
      if (object.properties['data'] case final data?) return data;
      for (final part in object.allOf) {
        final resolved = _context.model.resolveSchema(part);
        if (resolved is! SchemaObject) continue;
        if (search(resolved) case final data?) return data;
      }
      return null;
    }

    return search(item);
  }

  /// Whether [schema] is a reference that cannot be followed: the
  /// unresolved reference is the error (TOA101), so nothing else is said
  /// about the schema.
  bool isBroken(Schema? schema) =>
      schema != null && _context.model.resolveSchema(schema) == null;

  /// [schema] at the end of its `$ref`s, without the wrappers that add
  /// nothing: an annotation-only `allOf`, a nullable `anyOf`.
  Schema? _plain(Schema schema) {
    final refs = RefFollower.of(_context.model);
    var current = _context.model.resolveSchema(schema);
    for (var i = 0; i < _maxWrappers && current is SchemaObject; i++) {
      final single = SchemaShapes.singleOf(current, refs: refs);
      if (single == null) break;
      current = _context.model.resolveSchema(single);
    }
    return current;
  }

  /// Reports that the data at [location] is neither text nor JSON with a
  /// `contentSchema` (TOA666): it is read as text.
  void unread(SpecLocation location) => _context.report(
    .eventItemSchemaUnread,
    'The itemSchema does not say what the data of an event is: it needs a '
    '"data" property that is a string, or JSON with a "contentSchema"; the '
    'data is read as text.',
    location,
    fix:
        'Give "data" contentMediaType: application/json and a '
        'contentSchema at the source.',
  );

  /// The type of JSON data of [schema]; null when it is a plain string,
  /// which an event carries as text, not as a JSON string.
  DartType? json(Schema schema, NameHint hint) {
    final type = _mapper.typeOf(schema, hint, direction: .response);
    return type == const CoreType(.string) ? null : type;
  }
}
