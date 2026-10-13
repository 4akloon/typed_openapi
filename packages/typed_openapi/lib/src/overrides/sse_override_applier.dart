import '../model/media_type_name.dart';
import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
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
/// response is shared, so it is not. An `sse` field that finds no event
/// stream to apply to is TOA669.
final class SseOverrideApplier {
  /// Creates an applier that works in [_context].
  const SseOverrideApplier(this._context);

  final OverrideEditContext _context;

  /// The edits of the `sse` field of [target].
  Iterable<OverrideEdit> edits(OperationTarget target) sync* {
    final entry = target.entry;
    final sse = entry.sse;
    if (sse == null) return;
    final media = _eventStreams(target.node.location);
    if (media.isEmpty) {
      _context.report(
        .sseOverrideNotApplied,
        entry,
        'sse',
        'The operation has no 2xx response written in it whose content is '
            'text/event-stream, so "sse" changes nothing.',
        fix:
            'Remove "sse", or override a shared response through its own '
            'operation.',
      );
      return;
    }
    final schema = _schemaOf(sse);
    if (schema == null) return;
    for (final (at, raw) in media) {
      yield OverrideEdit(SpecEdit.add(at.child('schema'), schema), [
        (entry, 'sse'),
      ]);
      if (raw.containsKey('itemSchema')) {
        yield OverrideEdit(SpecEdit.remove(at.child('itemSchema')), [
          (entry, 'sse'),
        ]);
      }
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
