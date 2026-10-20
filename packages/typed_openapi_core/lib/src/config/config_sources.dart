import '../diagnostics/json_pointer.dart';

/// The maps a client's settings come from, `defaults` first and the
/// client's own last, each with its pointer.
extension type const ConfigSources(
  List<(Map<String, Object?>, JsonPointer)> _maps
)
    implements List<(Map<String, Object?>, JsonPointer)> {
  /// The value of [key] (or of [key] in [section]) from the last source
  /// that has it, with its pointer.
  (Object?, JsonPointer)? pick(String key, [String? section]) {
    for (final (map, at) in _maps.reversed) {
      if (section == null) {
        if (map.containsKey(key)) return (map[key], at.child(key));
        continue;
      }
      final inner = map[section];
      if (inner is Map<String, Object?> && inner.containsKey(key)) {
        return (inner[key], at.child(section).child(key));
      }
    }
    return null;
  }
}
