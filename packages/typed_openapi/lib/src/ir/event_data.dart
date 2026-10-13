import '../model/media_type.dart';
import '../model/media_type_name.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/sse_override.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'response_secrets.dart';
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
  /// Creates the reader; it maps types with [_mapper].
  EventData(this._context, this._mapper) : _secrets = ResponseSecrets(_context);

  static const _names = DartNames();

  final IrContext _context;
  final SchemaMapper _mapper;
  final ResponseSecrets _secrets;

  /// The events of [media] at [location]; inline schemas are named after
  /// [prefix]. The `events` of an [sse] override, written into the media
  /// type's `schema` as an object of the events, are its union.
  EventShape of(
    MediaType? media,
    SpecLocation location,
    String prefix, {
    SseOverride? sse,
  }) {
    if (media == null) return (data: null, union: null);
    if (sse?.events case final events?) {
      if (_fromOverride(events, media, location, prefix) case final union?) {
        return (data: null, union: union);
      }
    }
    if (media.itemSchema case final item?) {
      return _fromItem(item, location.child('itemSchema'), prefix);
    }
    final schema = media.schema;
    if (schema == null) return (data: null, union: null);
    final hint = NameHint(prefix, 'Event');
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
      return (data: _json(resolved.items!, hint), union: null);
    }
    return (data: _json(schema, hint), union: null);
  }

  /// The events an `itemSchema` gives: a union by event name, JSON in a
  /// `contentSchema`, else text, reported when `data` says neither.
  EventShape _fromItem(Schema item, SpecLocation location, String prefix) {
    final resolved = _context.model.resolveSchema(item);
    if (resolved is SchemaObject) {
      if (_union(resolved, location, prefix) case final union?) {
        return (data: null, union: union);
      }
      final data = resolved.properties['data'];
      if (_dataOf(data, NameHint(prefix, 'Event')) case (final type,)) {
        return (data: type, union: null);
      }
    }
    _unread(location);
    return (data: null, union: null);
  }

  /// The type of the event data [data] describes, as a one-element record:
  /// JSON in a `contentSchema` with a JSON `contentMediaType`, or null for
  /// a string; null itself when [data] says neither.
  (DartType?,)? _dataOf(Schema? data, NameHint hint) {
    final schema = data == null ? null : _context.model.resolveSchema(data);
    if (schema is! SchemaObject) return null;
    final contentSchema = schema.contentSchema;
    final mediaType = schema.contentMediaType;
    if (contentSchema != null &&
        mediaType != null &&
        MediaTypeName(mediaType).isJson) {
      return (_json(contentSchema, hint),);
    }
    if (contentSchema == null &&
        mediaType == null &&
        (schema.types.isEmpty || schema.types.contains(SchemaType.string))) {
      return (null,);
    }
    return null;
  }

  /// The union of an `itemSchema` whose `oneOf` (or `anyOf`) branches each
  /// fix `event` to a string constant; null for any other `itemSchema`.
  /// A repeated event name is reported (TOA667) and its later branch left
  /// out.
  EventUnionIr? _union(
    SchemaObject item,
    SpecLocation location,
    String prefix,
  ) {
    final key = item.oneOf.isNotEmpty ? 'oneOf' : 'anyOf';
    final named = _branches(item.oneOf.isNotEmpty ? item.oneOf : item.anyOf);
    if (named == null) return null;
    final variants = <EventVariantIr>[];
    final seen = <String>{};
    for (final (index, (event, branch)) in named.indexed) {
      final at = location.child(key).child(index);
      if (!seen.add(event)) {
        _context.report(
          .eventNameDuplicate,
          'Another branch of the itemSchema is the event "$event" already; '
          'this branch is left out.',
          at,
          fix: 'Give each event its own name at the source.',
        );
        continue;
      }
      variants.add(_variant(event, branch, at, prefix, index));
    }
    return EventUnionIr(
      variants,
      location: location,
      // The data of an unknown event is text that may be any event's.
      unknownSensitive: named.any((e) {
        final data = _dataSchema(e.$2);
        return data != null && _secrets.carriesSecret(data);
      }),
    );
  }

  /// The [branches] of a union with the event name each fixes; null when
  /// there are none or one fixes no name.
  List<(String, SchemaObject)>? _branches(List<Schema> branches) {
    if (branches.isEmpty) return null;
    final named = <(String, SchemaObject)>[];
    for (final branch in branches) {
      final resolved = _context.model.resolveSchema(branch);
      final event = resolved is SchemaObject ? _eventName(resolved) : null;
      if (resolved is! SchemaObject || event == null) return null;
      named.add((event, resolved));
    }
    return named;
  }

  /// The union of the override's [events] from the properties of the
  /// media type's `schema`; null when the override was not written there
  /// (its response is shared).
  EventUnionIr? _fromOverride(
    Map<String, Map<String, Object?>?> events,
    MediaType media,
    SpecLocation location,
    String prefix,
  ) {
    final schema = media.schema;
    final resolved = schema == null
        ? null
        : _context.model.resolveSchema(schema);
    if (resolved is! SchemaObject) return null;
    final properties = resolved.properties;
    final variants = <EventVariantIr>[];
    for (final (index, MapEntry(key: event, :value))
        in events.entries.indexed) {
      final data = properties[event];
      if (value == null) {
        variants.add(EventVariantIr(event, hasData: false));
        continue;
      }
      if (data == null) return null;
      final words = _names.pascal(event) ?? 'Event${index + 1}';
      final type = _json(data, NameHint(prefix, 'Event${words}Data'));
      variants.add(
        EventVariantIr(
          event,
          data: type,
          sensitive: _secrets.isSecret(data, type ?? const CoreType(.string)),
        ),
      );
    }
    return EventUnionIr(
      variants,
      location: location.child('schema'),
      unknownSensitive: properties.values.any(_secrets.carriesSecret),
    );
  }

  /// The event name a branch fixes: `event: {const: x}` or a one-value
  /// `enum` of a string.
  String? _eventName(SchemaObject branch) {
    final event = branch.properties['event'];
    final schema = event == null ? null : _context.model.resolveSchema(event);
    if (schema is! SchemaObject) return null;
    return switch ((schema.constValue, schema.enumValues)) {
      ((final String name,), _) => name,
      (null, [final String name]) => name,
      _ => null,
    };
  }

  /// The variant of [event], from its [branch] at [at]: no data when the
  /// branch has no `data` or a `data` that is only `null`.
  EventVariantIr _variant(
    String event,
    SchemaObject branch,
    SpecLocation at,
    String prefix,
    int index,
  ) {
    final data = branch.properties['data'];
    final schema = data == null ? null : _context.model.resolveSchema(data);
    if (data == null ||
        schema is SchemaObject &&
            schema.types.length == 1 &&
            schema.types.single == SchemaType.nullType) {
      return EventVariantIr(event, hasData: false);
    }
    final words = _names.pascal(event) ?? 'Event${index + 1}';
    final read = _dataOf(data, NameHint(prefix, 'Event${words}Data'));
    if (read == null) _unread(at.child('properties').child('data'));
    final type = read?.$1;
    return EventVariantIr(
      event,
      data: type,
      sensitive: _secrets.isSecret(
        _dataSchema(branch),
        type ?? const CoreType(.string),
      ),
    );
  }

  /// The schema of the data of an event [branch]: its `contentSchema`, else
  /// its `data`.
  Schema? _dataSchema(SchemaObject branch) {
    final data = branch.properties['data'];
    final schema = data == null ? null : _context.model.resolveSchema(data);
    return switch (schema) {
      SchemaObject(:final contentSchema?) => contentSchema,
      _ => data,
    };
  }

  void _unread(SpecLocation location) => _context.report(
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
  DartType? _json(Schema schema, NameHint hint) {
    final type = _mapper.typeOf(schema, hint, direction: .response);
    return type == const CoreType(.string) ? null : type;
  }
}
