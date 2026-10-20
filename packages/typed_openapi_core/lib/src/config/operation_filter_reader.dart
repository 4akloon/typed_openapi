import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'config_keys.dart';
import 'config_reading.dart';
import 'config_sources.dart';
import 'generation_config.dart';

/// Reads the operation filters `include` and `exclude` (R5.4) from the last
/// source whose value is a mapping. A bad value is reported through the
/// `invalid` function (TOA902) and the next source is tried.
final class OperationFilterReader {
  /// Creates a reader of [_sources] that reports a bad value through
  /// [_invalid] and an unknown key through [_checkKeys]; [_spanAt] gives a
  /// pattern its place in the config file.
  const OperationFilterReader(
    this._sources,
    this._invalid,
    this._checkKeys,
    this._spanAt,
  );

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  final void Function(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  )
  _checkKeys;

  final SourceSpan? Function(JsonPointer at) _spanAt;

  /// The filter under [key]: `include` or `exclude`.
  OperationFilter read(String key) {
    final (:value, :at) = _sources.resolve<Map<String, Object?>>(
      key,
      builtIn: const {},
      show: _describe,
      report: _invalid,
      read: (value) => _mapping(key, value),
    );
    _checkUnknownKeys(key, appliedAt: at);
    if (at == null) return const OperationFilter();
    return OperationFilter(
      tags: _patterns(value, 'tags', at),
      operations: _patterns(value, 'operations', at),
      paths: _patterns(value, 'paths', at),
    );
  }

  /// Reports the unknown keys of the filters that were rejected or applied,
  /// from the client outward to the source at [appliedAt] (all of them when
  /// that is null); a filter a valid later source shadows is not read.
  void _checkUnknownKeys(String key, {required JsonPointer? appliedAt}) {
    for (final (map, mapAt) in _sources.reversed) {
      final at = mapAt.child(key);
      if (map[key] case final Map<String, Object?> filter) {
        _checkKeys(filter, ConfigKeys.filter, at);
      }
      if (at.value == appliedAt?.value) return;
    }
  }

  String _describe(Map<String, Object?> filter) {
    final parts = [
      for (final MapEntry(:key, :value) in filter.entries)
        if (value is List<Object?> && ConfigKeys.filter.contains(key))
          '$key: ${value.join(', ')}',
    ];
    return parts.isEmpty ? 'no filter' : parts.join('; ');
  }

  ConfigReading<Map<String, Object?>> _mapping(String key, Object? value) {
    if (value is! Map<String, Object?>) {
      return InvalidValue('"$key" must be a mapping.');
    }
    for (final name in const ['tags', 'operations', 'paths']) {
      if (value[name] case final list? when list is! List<Object?>) {
        return InvalidValue(
          '"$name" must be a list of strings.',
          child: name,
        );
      }
    }
    return ValidValue(value);
  }

  List<FilterPattern> _patterns(
    Map<String, Object?> filter,
    String name,
    JsonPointer at,
  ) {
    final list = filter[name];
    if (list is! List<Object?>) return const [];
    final result = <FilterPattern>[];
    for (final (i, item) in list.indexed) {
      final pointer = at.child(name).child(i);
      if (item is String && item.isNotEmpty) {
        result.add(FilterPattern(item, pointer, _spanAt(pointer)));
      } else {
        _invalid('Each entry must be a non-empty string.', pointer);
      }
    }
    return result;
  }
}
