import '../model/media_type_name.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir_context.dart';
import 'schema_mapper.dart';

/// Reads what the data of one event is (decision 1 of M10): JSON in a
/// `contentSchema`, a string as text, or neither (TOA666).
final class EventDataReader {
  /// Creates the reader; it maps types with [_mapper].
  const EventDataReader(this._context, this._mapper);

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The type of the event data [data] describes, as a one-element record:
  /// JSON in a `contentSchema` with a JSON `contentMediaType`, or null for
  /// a string; null itself when [data] says neither.
  (DartType?,)? read(Schema? data, NameHint hint) {
    final schema = data == null ? null : _context.model.resolveSchema(data);
    if (schema is! SchemaObject) return null;
    final contentSchema = schema.contentSchema;
    final mediaType = schema.contentMediaType;
    if (contentSchema != null &&
        mediaType != null &&
        MediaTypeName(mediaType).isJson) {
      return (json(contentSchema, hint),);
    }
    if (contentSchema == null &&
        mediaType == null &&
        (schema.types.isEmpty || schema.types.contains(SchemaType.string))) {
      return (null,);
    }
    return null;
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
