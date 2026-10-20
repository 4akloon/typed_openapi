import '../diagnostics/json_pointer.dart';
import 'config_reading.dart';

/// The maps a client's settings come from, `defaults` first and the
/// client's own last, each with its pointer.
extension type const ConfigSources(
  List<(Map<String, Object?>, JsonPointer)> _maps
)
    implements List<(Map<String, Object?>, JsonPointer)> {
  /// The value of [key] (or of [key] in [section]) from the last source
  /// whose value [read] accepts, else [builtIn].
  ///
  /// A source whose value [read] rejects acts as if it lacked the key, and
  /// the problem is reported through [report] with the value that is
  /// applied instead: the one from `defaults`, else the built-in [builtIn]
  /// (written by [show]). The pointer is that of the applied source, null
  /// for [builtIn].
  ({T value, JsonPointer? at}) resolve<T>(
    String key, {
    required ConfigReading<T> Function(Object?) read,
    required T builtIn,
    required void Function(String message, JsonPointer at) report,
    String? section,
    String Function(T)? show,
  }) {
    final rejected = <(String, JsonPointer)>[];
    var used = (value: builtIn, at: null as JsonPointer?);
    for (final (map, mapAt) in _maps.reversed) {
      final entry = _entryOf(map, mapAt, key, section);
      if (entry == null) continue;
      final (value, at) = entry;
      switch (read(value)) {
        case ValidValue<T>(value: final accepted):
          used = (value: accepted, at: at);
        case InvalidValue<T>(:final problem, :final child):
          rejected.add((problem, child == null ? at : at.child(child)));
      }
      if (used.at != null) break;
    }
    final shown = show ?? (T value) => '$value';
    final replacement = rejected.isEmpty || used.at == null
        ? 'The default (${shown(used.value)}) is used.'
        : 'The value from "defaults" (${shown(used.value)}) is used.';
    for (final (problem, at) in rejected) {
      report('$problem $replacement', at);
    }
    return used;
  }

  (Object?, JsonPointer)? _entryOf(
    Map<String, Object?> map,
    JsonPointer at,
    String key,
    String? section,
  ) {
    if (section == null) {
      return map.containsKey(key) ? (map[key], at.child(key)) : null;
    }
    final inner = map[section];
    if (inner is Map<String, Object?> && inner.containsKey(key)) {
      return (inner[key], at.child(section).child(key));
    }
    return null;
  }
}
