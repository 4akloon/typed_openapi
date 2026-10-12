import 'package:collection/collection.dart';

import '../load/openapi_version.dart';

/// A nullable schema: a `$ref` with `nullable: true` (3.0), or one or more
/// branches next to a null branch (3.1), with the keys around them.
final class NullableShape {
  /// Reads the shape of [raw] whose nullable form is [key] with [branches].
  const NullableShape(this.raw, this.key, this.branches);

  /// Keys a null branch may have besides `type`.
  static const _annotations = {
    'type',
    'description',
    'title',
    r'$comment',
    'default',
    'deprecated',
    'example',
    'examples',
    'readOnly',
    'writeOnly',
  };

  /// The nullable form of [raw] for the dialect of [version]: a `$ref` in
  /// `allOf` next to `nullable: true` in 3.0; from 3.1 an `anyOf` or `oneOf`
  /// of one or more branches and a null schema; any other keys are siblings.
  /// Null for any other schema.
  static NullableShape? of(Map<String, Object?> raw, OpenApiVersion version) =>
      version == .v30 ? _referenceForm(raw) : _unionForm(raw);

  static NullableShape? _referenceForm(Map<String, Object?> raw) {
    final list = raw['allOf'];
    if (raw['nullable'] != true || list is! List<Object?> || list.length != 1) {
      return null;
    }
    final branch = list.single;
    return branch is Map<String, Object?> &&
            branch.length == 1 &&
            branch[r'$ref'] is String
        ? NullableShape(raw, 'allOf', [branch])
        : null;
  }

  static NullableShape? _unionForm(Map<String, Object?> raw) {
    for (final key in ['anyOf', 'oneOf']) {
      final list = raw[key];
      if (list is! List<Object?> || list.length < 2) continue;
      final branches = <Map<String, Object?>>[];
      var nulls = 0;
      for (final item in list) {
        if (item is! Map<String, Object?>) {
          nulls = 0;
          break;
        }
        if (_isNullSchema(item)) {
          nulls++;
        } else {
          branches.add(item);
        }
      }
      if (nulls > 0 && branches.isNotEmpty) {
        return NullableShape(raw, key, branches);
      }
    }
    return null;
  }

  /// Whether [schema] allows only `null`: `type: 'null'`, with no keys but
  /// annotations.
  static bool _isNullSchema(Map<String, Object?> schema) =>
      schema['type'] == 'null' &&
      schema.keys.every(
        (key) => _annotations.contains(key) || key.startsWith('x-'),
      );

  /// The schema.
  final Map<String, Object?> raw;

  /// `allOf` (3.0), `anyOf` or `oneOf` (3.1).
  final String key;

  /// The branches that are not `null`.
  final List<Map<String, Object?>> branches;

  /// The schema without nullability, less a `default` that is `null`: one
  /// branch is merged with the other keys, several stay under [key]. Null
  /// when one branch and the other keys set one key to different values.
  Map<String, Object?>? withoutNull() {
    final siblings = {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key != this.key &&
            key != 'nullable' &&
            !(key == 'default' && value == null))
          key: value,
    };
    if (branches.length > 1) {
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key == this.key)
            key: branches
          else if (siblings.containsKey(key))
            key: value,
      };
    }
    for (final MapEntry(:key, :value) in branches.single.entries) {
      if (siblings.containsKey(key) &&
          !const DeepCollectionEquality().equals(siblings[key], value)) {
        return null;
      }
    }
    return {...branches.single, ...siblings};
  }
}
