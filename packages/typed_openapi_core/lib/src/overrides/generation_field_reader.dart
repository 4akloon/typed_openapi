import '../diagnostics/json_pointer.dart';
import 'override_field_reader.dart';
import 'override_keys.dart';
import 'override_set.dart';

/// Reads the generation fields several kinds of entry share (`union` and
/// `dartType`), as opposed to the spec fields.
final class GenerationFieldReader {
  /// Creates a reader that works through [_fields].
  const GenerationFieldReader(this._fields);

  final OverrideFieldReader _fields;

  /// The `union` mode of [entry]; null when absent or invalid.
  UnionMode? unionMode(Map<String, Object?> entry, JsonPointer at) {
    if (!entry.containsKey('union')) return null;
    final value = entry['union'];
    for (final mode in UnionMode.values) {
      if (value == mode.name) return mode;
    }
    _fields.invalid('"union" must be raw or structural.', at.child('union'));
    return null;
  }

  /// The `dartType` record of [entry]; null when absent or unusable.
  DartTypeOverride? dartType(Map<String, Object?> entry, JsonPointer at) {
    final value = _fields.map(entry, 'dartType', at);
    if (value == null) return null;
    final p = at.child('dartType');
    _fields.checkKeys(value, OverrideKeys.dartType, p);
    final type = _fields.string(value, 'type', p, required: true);
    final import = _fields.string(value, 'import', p, required: true);
    final converter = _fields.string(value, 'converter', p);
    // A converter that is written but unusable was reported: the record
    // is not applied without it.
    if (type == null || import == null) return null;
    if (converter == null && value.containsKey('converter')) return null;
    var valid = true;
    for (final (field, written) in [
      ('type', type),
      ('import', import),
      if (converter != null) ('converter', converter),
    ]) {
      if (DartTypeOverride.problem(field, written) case final problem?) {
        _fields.invalid(problem, p.child(field));
        valid = false;
      }
    }
    if (!valid) return null;
    return DartTypeOverride(type: type, import: import, converter: converter);
  }
}
