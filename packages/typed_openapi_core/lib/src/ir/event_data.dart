import '../model/media_type.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/sse_override.dart';
import 'dart_type.dart';
import 'event_data_reader.dart';
import 'event_union_reader.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'override_events.dart';
import 'schema_mapper.dart';

/// What the events of a stream are: one data type for all ([data], null for
/// text), or a [union] keyed by the event name.
typedef EventShape = ({DartType? data, EventUnionIr? union});

/// The type of the data of each event of a `text/event-stream` media type
/// (decisions 1 and 2 of M10): `itemSchema` (OpenAPI 3.2) describes the
/// whole event and its `data` property the data, or, as a `oneOf` whose
/// branches fix `event` to a constant, one event each; `schema`, the
/// code-first practice, describes the JSON in `data`, an array its items.
final class EventData {
  /// Creates the reader; it maps types with [mapper].
  EventData(IrContext context, SchemaMapper mapper)
    : this._(
        context,
        EventDataReader(context, mapper),
        OverrideEvents(context, mapper),
      );

  EventData._(this._context, this._data, this._overrideEvents)
    : _unions = EventUnionReader(_context, _data);

  final IrContext _context;
  final EventDataReader _data;
  final OverrideEvents _overrideEvents;
  final EventUnionReader _unions;

  /// The events of [media] at [location]; inline schemas are named after
  /// [prefix]. The `events` of an [sse] override, which the caller passes
  /// only for a media type written in the operation, are its union.
  EventShape of(
    MediaType? media,
    SpecLocation location,
    String prefix, {
    SseOverride? sse,
  }) {
    if (media == null) return (data: null, union: null);
    final overridden = sse == null
        ? null
        : _overrideEvents.of(sse, media, location, prefix);
    if (overridden != null) return (data: null, union: overridden);
    if (media.itemSchema case final item?) {
      return _fromItem(item, location.child('itemSchema'), prefix);
    }
    final schema = media.schema;
    if (schema == null) return (data: null, union: null);
    final hint = NameHint(prefix, 'Event');
    final resolved = _context.model.resolveSchema(schema);
    if (resolved case SchemaObject(
      :final items?,
    ) when resolved.types.contains(SchemaType.array)) {
      _context.report(
        .eventDataArrayItems,
        'The event stream\'s schema is an array; the data of each event is '
        'taken to be one of its items.',
        location.child('schema'),
        fix: 'Describe one event at the source (itemSchema in OpenAPI 3.2).',
      );
      return (data: _data.ofSchema(items, hint), union: null);
    }
    return (data: _data.ofSchema(schema, hint), union: null);
  }

  /// The events an `itemSchema` gives: a union by event name, JSON in a
  /// `contentSchema`, else text, reported when `data` says neither.
  EventShape _fromItem(Schema item, SpecLocation location, String prefix) {
    final resolved = _context.model.resolveSchema(item);
    // A reference that cannot be followed has its own error (TOA101).
    if (resolved == null) return (data: null, union: null);
    if (resolved is SchemaObject) {
      if (_unions.union(resolved, location, prefix) case final union?) {
        return (data: null, union: union);
      }
      final data = _data.dataOf(resolved);
      if (_data.read(data, NameHint(prefix, 'Event')) case (final type,)) {
        return (data: type, union: null);
      }
      // A union's branches are reported one by one, and a broken reference
      // is reported where it is written.
      final hasBranches =
          resolved.oneOf.isNotEmpty || resolved.anyOf.isNotEmpty;
      if (data == null ? hasBranches : _data.isBroken(data)) {
        return (data: null, union: null);
      }
    }
    _data.unread(location);
    return (data: null, union: null);
  }
}
