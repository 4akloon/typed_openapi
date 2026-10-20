import '../model/media_type.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/sse_override.dart';
import 'dart_type.dart';
import 'event_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'response_secrets.dart';
import 'schema_mapper.dart';

/// Reads the `events` of an `sse` override: the applier wrote them into the
/// media type's `schema` as an object whose properties are the events with
/// data, and this builds the union from that object in the override's order.
final class OverrideEvents {
  /// Creates the reader; it maps types with [_mapper].
  OverrideEvents(this._context, this._mapper)
    : _secrets = ResponseSecrets(_context);

  static const _names = DartNames();

  final IrContext _context;
  final SchemaMapper _mapper;
  final ResponseSecrets _secrets;

  /// The union of the events of [sse] from the properties of the `schema`
  /// of [media] at [location]; null when there is none to read. An event
  /// whose data the properties lack (a name the parser drops, `<<`) is left
  /// out and reported (TOA669).
  EventUnionIr? of(
    SseOverride sse,
    MediaType media,
    SpecLocation location,
    String prefix,
  ) {
    final events = sse.events;
    final schema = media.schema;
    final resolved = schema == null
        ? null
        : _context.model.resolveSchema(schema);
    if (events == null || resolved is! SchemaObject) return null;
    final properties = resolved.properties;
    final at = location.child('schema');
    final variants = <EventVariantIr>[];
    for (final (index, MapEntry(key: event, :value))
        in events.entries.indexed) {
      final data = properties[event];
      if (EventNames.unreachable(event) case final reason?) {
        _reportUnreachable(sse, event, reason);
      } else if (value == null) {
        variants.add(EventVariantIr(event, location: at, hasData: false));
      } else if (data == null) {
        _reportLeftOut(sse, event);
      } else {
        variants.add(_variant(event, data, at, index, prefix));
      }
    }
    if (variants.isEmpty) return null;
    return EventUnionIr(
      variants,
      location: at,
      unknownSensitive: properties.values.any(_secrets.carriesSecret),
    );
  }

  EventVariantIr _variant(
    String event,
    Schema data,
    SpecLocation at,
    int index,
    String prefix,
  ) {
    final words = _names.pascal(event) ?? 'Event${index + 1}';
    final mapped = _mapper.typeOf(
      data,
      NameHint(prefix, 'Event${words}Data'),
      direction: .response,
    );
    final type = mapped == const CoreType(.string) ? null : mapped;
    return EventVariantIr(
      event,
      location: at,
      data: type,
      sensitive: _secrets.isSecret(data, type ?? const CoreType(.string)),
    );
  }

  void _reportUnreachable(SseOverride sse, String event, String reason) =>
      _context.reportAtPointer(
        .eventNameUnreachable,
        EventNames.message(reason),
        sse.pointer.child('events').child(event),
        fix: EventNames.fix,
      );

  void _reportLeftOut(SseOverride sse, String event) {
    _context.reportAtPointer(
      .sseOverrideNotApplied,
      'An event of "sse.events" has data, but the schema written for the '
      'events has no property of that name (the reader drops the YAML merge '
      'key "<<"), so its data cannot be read; the event is left out.',
      sse.pointer.child('events').child(event),
      fix: 'Rename the event, or remove it from "events".',
    );
  }
}
