import '../snapshot/api_snapshot.dart';

/// The ready `name:` override for a schema that a spec renamed (M12,
/// decision 7): the rename is not guessed, it is reported as removed and
/// added, and the fix keeps the old Dart name on the new schema.
final class RenameHints {
  /// Creates the hints for the change from [_before] to [_after].
  RenameHints(this._before, this._after);

  final ApiSnapshot _before;
  final ApiSnapshot _after;

  static final _component = RegExp(r'^([^#]*)#/components/schemas/([^/@]+)$');
  static final _plainKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$');

  /// The override that gives the schema that replaced the removed type
  /// [id] its old name: the one component schema of the same kind added in
  /// the same file, else a template with `<NewKey>`; null when [id] is not
  /// a component schema.
  String? fixFor(String id) {
    final match = _component.firstMatch(id);
    final old = _before.types[id];
    if (match == null || old == null) return null;
    final file = match[1]!;
    final added = [
      for (final MapEntry(key: other, value: type) in _after.types.entries)
        if (!_before.types.containsKey(other) && type.kind == old.kind)
          if (_component.firstMatch(other) case final m? when m[1] == file)
            _unescape(m[2]!),
    ];
    final key = added.length == 1 ? _yamlKey(added.single) : '<NewKey>';
    return 'schemas:\n  $key:\n    name: ${old.name}';
  }

  /// A JSON pointer token as text.
  static String _unescape(String token) =>
      token.replaceAll('~1', '/').replaceAll('~0', '~');

  static String _yamlKey(String key) =>
      _plainKey.hasMatch(key) ? key : "'${key.replaceAll("'", "''")}'";
}
