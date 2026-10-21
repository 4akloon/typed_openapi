import '../diagnostics/message_text.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'event_data_reader.dart';
import 'event_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'pending_declaration.dart';
import 'response_secrets.dart';

/// Reads the union of an `itemSchema` whose `oneOf` (or `anyOf`) branches
/// each fix `event` to a string constant (decision 2 of M10): a variant per
/// branch, typed by its `data`.
final class EventUnionReader {
  /// Creates the reader; it reads each event's data through [_data].
  EventUnionReader(this._context, this._data)
    : _secrets = ResponseSecrets(_context);

  static const _names = DartNames();

  final IrContext _context;
  final EventDataReader _data;
  final ResponseSecrets _secrets;

  /// The union of [item], described at [location], with the types of
  /// inline data named after [prefix]; null for any other `itemSchema`.
  /// A repeated event name is reported (TOA667) and its later branch left
  /// out.
  EventUnionIr? union(SchemaObject item, SpecLocation location, String prefix) {
    final key = item.oneOf.isNotEmpty ? 'oneOf' : 'anyOf';
    final named = _branches(
      item.oneOf.isNotEmpty ? item.oneOf : item.anyOf,
      location.child(key),
    );
    if (named == null) return null;
    final variants = <EventVariantIr>[];
    final seen = <String>{};
    for (final (index, (event, branch)) in named.indexed) {
      final at = location.child(key).child(index);
      if (_isLeftOut(event, at, seen)) continue;
      variants.add(_variant(event, branch, at, prefix, index));
    }
    if (variants.isEmpty) return null;
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

  /// Whether the branch of [event] at [at] is left out, reported: the name
  /// is [seen] already (TOA667) or no `event:` line can carry it (TOA670).
  bool _isLeftOut(String event, SpecLocation at, Set<String> seen) {
    if (EventNames.unreachable(event) case final reason?) {
      _context.report(
        .eventNameUnreachable,
        EventNames.message(reason),
        at,
        fix: EventNames.fix,
      );
      return true;
    }
    if (seen.add(event)) return false;
    _context.report(
      .eventNameDuplicate,
      'Another branch of the itemSchema is the event '
      '${MessageText.quote(event)} already; '
      'this branch is left out.',
      at,
      fix: 'Give each event its own name at the source.',
    );
    return true;
  }

  /// The [branches] of a union at [at] with the event name each fixes; null
  /// when there are none or one fixes no name, which is reported (TOA666)
  /// for each such branch.
  List<(String, SchemaObject)>? _branches(
    List<Schema> branches,
    SpecLocation at,
  ) {
    if (branches.isEmpty) return null;
    final named = <(String, SchemaObject)>[];
    var isComplete = true;
    for (final (index, branch) in branches.indexed) {
      final resolved = _context.model.resolveSchema(branch);
      final event = resolved is SchemaObject ? _eventName(resolved) : null;
      if (resolved is SchemaObject && event != null) {
        named.add((event, resolved));
        continue;
      }
      isComplete = false;
      // An unresolved reference has its own error (TOA101).
      if (resolved != null) _reportUnnamed(at.child(index));
    }
    return isComplete ? named : null;
  }

  void _reportUnnamed(SpecLocation at) => _context.report(
    .eventItemSchemaUnread,
    'This branch of the itemSchema does not fix its "event" to a string '
    'constant (const, or an enum of one value), so the events cannot be '
    'told apart by name; the data is read as text.',
    at,
    fix:
        'Write properties.event.const in the branch itself: a branch '
        'written with allOf does not count.',
  );

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
      return EventVariantIr(event, location: at, hasData: false);
    }
    final words = _names.eventPascal(event) ?? 'Event${index + 1}';
    final read = _data.read(data, NameHint(prefix, 'Event${words}Data'));
    if (read == null && !_data.isBroken(data)) {
      _data.unread(at.child('properties').child('data'));
    }
    final type = read?.$1;
    return EventVariantIr(
      event,
      location: at,
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
}
