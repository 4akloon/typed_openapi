import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
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

  static const _filterKeys = {'tags', 'operations', 'paths'};

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
      show: (_) => 'no filter',
      report: _invalid,
      read: (value) => _mapping(key, value),
    );
    if (at == null) return const OperationFilter();
    _checkKeys(value, _filterKeys, at);
    return OperationFilter(
      tags: _patterns(value, 'tags', at),
      operations: _patterns(value, 'operations', at),
      paths: _patterns(value, 'paths', at),
    );
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
