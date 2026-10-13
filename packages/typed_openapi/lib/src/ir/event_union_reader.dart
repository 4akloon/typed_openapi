import '../diagnostics/message_text.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'event_data_reader.dart';
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
    final named = _branches(item.oneOf.isNotEmpty ? item.oneOf : item.anyOf);
    if (named == null) return null;
    final variants = <EventVariantIr>[];
    final seen = <String>{};
    for (final (index, (event, branch)) in named.indexed) {
      final at = location.child(key).child(index);
      if (!seen.add(event)) {
        _context.report(
          .eventNameDuplicate,
          'Another branch of the itemSchema is the event '
          '${MessageText.quote(event)} already; '
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
    final read = _data.read(data, NameHint(prefix, 'Event${words}Data'));
    if (read == null) _data.unread(at.child('properties').child('data'));
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
}
