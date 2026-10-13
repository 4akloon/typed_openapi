import '../diagnostics/json_pointer.dart';
import 'override_field_reader.dart';
import 'sse_override.dart';

/// Reads the `sse` field of an operation override (decision 6 of M10):
/// `data` or `events`, `unknown`, `reconnect` and `method`, in camelCase;
/// an unknown key is TOA803 with the closest allowed key, a bad value
/// TOA802 and ignored.
final class SseOverrideReader {
  /// Creates a reader that works through [_fields].
  const SseOverrideReader(this._fields);

  final OverrideFieldReader _fields;

  static const _keys = {'data', 'events', 'unknown', 'reconnect', 'method'};

  /// The `sse` field of [entry] at [at]; null when absent or not a mapping.
  SseOverride? read(Map<String, Object?> entry, JsonPointer at) {
    final sse = _fields.map(entry, 'sse', at);
    if (sse == null) return null;
    final p = at.child('sse');
    _fields.checkKeys(sse, _keys, p);
    var data = sse.containsKey('data')
        ? _schema(sse['data'], p.child('data'))
        : null;
    var events = _events(sse, p);
    if (data != null && events != null) {
      _fields.invalid(
        '"data" and "events" exclude each other: one type for every event, '
        'or a type per event name; both are ignored.',
        p,
        fix: 'Keep one of them.',
      );
      data = null;
      events = null;
    }
    return SseOverride(
      pointer: p,
      data: data,
      events: events,
      keepUnknown: _unknown(sse, p),
      reconnect: _fields.boolean(sse, 'reconnect', p),
      method: _method(sse, p),
    );
  }

  /// The schema [value] at [at] names: a `components.schemas` key or an
  /// inline schema.
  Map<String, Object?>? _schema(Object? value, JsonPointer at) {
    switch (value) {
      case final String name when name.isNotEmpty:
        return SseOverride.component(name);
      case final Map<String, Object?> schema:
        return schema;
    }
    _fields.invalid(
      'An event schema is a components.schemas key or an inline schema.',
      at,
    );
    return null;
  }

  Map<String, Map<String, Object?>?>? _events(
    Map<String, Object?> sse,
    JsonPointer at,
  ) {
    if (!sse.containsKey('events')) return null;
    final value = sse['events'];
    if (value is! Map<String, Object?> || value.isEmpty) {
      _fields.invalid(
        '"events" maps event names to schemas, null for an event without '
        'data.',
        at.child('events'),
      );
      return null;
    }
    final events = <String, Map<String, Object?>?>{};
    for (final MapEntry(key: name, value: schema) in value.entries) {
      if (schema == null) {
        events[name] = null;
      } else if (_schema(schema, at.child('events').child(name))
          case final read?) {
        events[name] = read;
      }
    }
    return events;
  }

  bool? _unknown(Map<String, Object?> sse, JsonPointer at) {
    if (!sse.containsKey('unknown')) return null;
    return switch (sse['unknown']) {
      'keep' => true,
      'ignore' => false,
      _ => _invalid('"unknown" must be keep or ignore.', at.child('unknown')),
    };
  }

  SseMethod? _method(Map<String, Object?> sse, JsonPointer at) {
    if (!sse.containsKey('method')) return null;
    for (final method in SseMethod.values) {
      if (sse['method'] == method.name) return method;
    }
    return _invalid(
      '"method" must be stream, only or none.',
      at.child('method'),
    );
  }

  /// Reports [message] at [at] and returns no value.
  T? _invalid<T>(String message, JsonPointer at) {
    _fields.invalid(message, at);
    return null;
  }
}
