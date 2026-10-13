import '../model/media_type.dart';
import '../model/media_type_name.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir_context.dart';
import 'schema_mapper.dart';

/// The type of the data of each event of a `text/event-stream` media type
/// (decision 1 of M10): `itemSchema` (OpenAPI 3.2) describes the whole
/// event and its `data` property the data; `schema`, the code-first
/// practice, describes the JSON in `data`, an array its items.
final class EventData {
  /// Creates the reader; it maps types with [_mapper].
  const EventData(this._context, this._mapper);

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The type of each event's data in [media] at [location]; null when the
  /// data is text. Inline schemas are named after [hint].
  DartType? of(MediaType? media, SpecLocation location, NameHint hint) {
    if (media == null) return null;
    if (media.itemSchema case final item?) {
      return _fromItem(item, location.child('itemSchema'), hint);
    }
    final schema = media.schema;
    if (schema == null) return null;
    final resolved = _context.model.resolveSchema(schema);
    if (resolved is SchemaObject &&
        resolved.types.contains(SchemaType.array) &&
        resolved.items != null) {
      _context.report(
        .eventDataArrayItems,
        'The event stream\'s schema is an array; the data of each event is '
        'taken to be one of its items.',
        location.child('schema'),
        fix: 'Describe one event at the source (itemSchema in OpenAPI 3.2).',
      );
      return _json(resolved.items!, hint);
    }
    return _json(schema, hint);
  }

  /// The data type an `itemSchema` gives: JSON in a `contentSchema`, else
  /// text, reported when `data` says neither.
  DartType? _fromItem(Schema item, SpecLocation location, NameHint hint) {
    final resolved = _context.model.resolveSchema(item);
    final data = resolved is SchemaObject ? resolved.properties['data'] : null;
    final schema = data == null ? null : _context.model.resolveSchema(data);
    if (schema is SchemaObject) {
      final contentSchema = schema.contentSchema;
      final mediaType = schema.contentMediaType;
      if (contentSchema != null &&
          mediaType != null &&
          MediaTypeName(mediaType).isJson) {
        return _json(contentSchema, hint);
      }
      if (contentSchema == null &&
          mediaType == null &&
          (schema.types.isEmpty || schema.types.contains(SchemaType.string))) {
        return null;
      }
    }
    _context.report(
      .eventItemSchemaUnread,
      'The itemSchema does not say what the data of an event is: it needs a '
      '"data" property that is a string, or JSON with a "contentSchema"; the '
      'data is read as text.',
      location,
      fix:
          'Give "data" contentMediaType: application/json and a '
          'contentSchema at the source.',
    );
    return null;
  }

  /// The type of JSON data of [schema]; null when it is a plain string,
  /// which an event carries as text, not as a JSON string.
  DartType? _json(Schema schema, NameHint hint) {
    final type = _mapper.typeOf(schema, hint, direction: .response);
    return type == const CoreType(.string) ? null : type;
  }
}
