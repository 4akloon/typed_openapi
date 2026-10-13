import '../model/media_type_name.dart';
import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_set.dart';
import 'override_target.dart';
import 'sse_override.dart';

/// The edits of the `sse` field of an operation override (decision 6 of
/// M10): `data` or `events` become the `schema` of every
/// `text/event-stream` media type of the operation's 2xx responses, and
/// their `itemSchema` goes, so that the override wins over both. `events`
/// is written as an object whose properties are the events with data; the
/// IR builder reads them in the override's order.
///
/// Only responses written in the operation are changed: a `$ref`'d
/// response is shared, so it is not. A `data` or `events` that finds no
/// event stream to write into is TOA669, naming that part; the other
/// fields of `sse` are generation fields the IR builder applies to the
/// operation whatever its responses are. A `data` or `events` the spec
/// already has is TOA807.
final class SseOverrideApplier {
  /// Creates an applier that works in [_context].
  const SseOverrideApplier(this._context);

  final OverrideEditContext _context;

  /// The edits of the `sse` field of [target].
  List<OverrideEdit> edits(OperationTarget target) {
    final entry = target.entry;
    final sse = entry.sse;
    final schema = sse == null ? null : _schemaOf(sse);
    if (sse == null || schema == null) return const [];
    final part = sse.data != null ? 'data' : 'events';
    final media = _eventStreams(target.node.location);
    if (media.isEmpty) {
      _context.report(
        .sseOverrideNotApplied,
        entry,
        'sse',
        'The "$part" of "sse" is not applied: it is written only into '
            'text/event-stream media types that a 2xx response written in '
            'the operation has, and this operation has none (a response '
            'that is a reference is shared).',
        fix:
            'Remove "$part", or override a shared response through its own '
            'operation.',
      );
      return const [];
    }
    final edits = [
      for (final (at, raw) in media) ..._edits(entry, at, raw, schema),
    ];
    // Only `data` has an unchanged form: the object `events` writes reads
    // as a union, which the same schema without it does not.
    if (edits.isEmpty && sse.data != null) {
      _context.report(
        .overrideUnchanged,
        entry,
        'sse',
        'The spec already has this "data"; the override changes nothing and '
            'can be removed.',
        fix: 'Remove "data" from "sse".',
      );
    }
    return edits;
  }

  /// The edits that make the media type at [at] ([raw]) have [schema] and
  /// no `itemSchema`.
  Iterable<OverrideEdit> _edits(
    OperationOverride entry,
    SpecLocation at,
    Map<String, Object?> raw,
    Map<String, Object?> schema,
  ) sync* {
    final hasItemSchema = raw.containsKey('itemSchema');
    if (hasItemSchema ||
        !OverrideEditContext.equality.equals(raw['schema'], schema)) {
      yield OverrideEdit(SpecEdit.add(at.child('schema'), schema), [
        (entry, 'sse'),
      ]);
    }
    if (hasItemSchema) {
      yield OverrideEdit(SpecEdit.remove(at.child('itemSchema')), [
        (entry, 'sse'),
      ]);
    }
  }

  /// The `schema` [sse] writes: `data`, or an object whose properties are
  /// the `events` with data; null when it has neither.
  static Map<String, Object?>? _schemaOf(SseOverride sse) {
    if (sse.data case final data?) return data;
    final events = sse.events;
    if (events == null) return null;
    return {
      'type': 'object',
      'properties': {
        for (final MapEntry(:key, :value) in events.entries) key: ?value,
      },
    };
  }

  /// The event-stream media types of the 2xx responses written in the
  /// operation at [operation], with their plain objects.
  List<(SpecLocation, Map<String, Object?>)> _eventStreams(
    SpecLocation operation,
  ) {
    final responses = switch (_context.object(operation)?['responses']) {
      final Map<String, Object?> responses => responses,
      _ => const <String, Object?>{},
    };
    return [
      for (final MapEntry(key: status, value: response) in responses.entries)
        if (status.startsWith('2') && response is Map<String, Object?>)
          if (response['content'] case final Map<String, Object?> content)
            for (final MapEntry(key: type, value: media) in content.entries)
              if (MediaTypeName(type).base == 'text/event-stream' &&
                  media is Map<String, Object?>)
                (
                  operation
                      .child('responses')
                      .child(status)
                      .child('content')
                      .child(type),
                  media,
                ),
    ];
  }
}
