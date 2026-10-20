import '../snapshot/api_snapshot.dart';
import 'api_change.dart';
import 'fact_changes.dart';
import 'member_changes.dart';
import 'rename_hints.dart';

/// Compares two snapshots of a client's API and sorts every change into a
/// [ChangeCategory] (M12, decision 2).
final class ApiDiff {
  /// Creates the comparer.
  const ApiDiff();

  static const _facts = FactChanges();
  static const _members = MemberChanges();

  /// The changes from [before] to [after], sorted.
  List<ApiChange> compare(ApiSnapshot before, ApiSnapshot after) {
    final old = before.types;
    final now = after.types;
    final hints = RenameHints(before, after);
    return [
      for (final MapEntry(key: id, value: type) in old.entries)
        if (!now.containsKey(id))
          ApiChange(
            .breaking,
            '${_label(type)} ${type.name} was removed.',
            type: id,
            fix: hints.fixFor(id),
          ),
      for (final MapEntry(key: id, value: type) in now.entries)
        if (!old.containsKey(id))
          ApiChange(
            .additive,
            '${_label(type)} ${type.name} was added.',
            type: id,
          ),
      for (final MapEntry(key: id, value: type) in old.entries)
        if (now[id] case final changed?) ..._changed(id, type, changed),
    ]..sort();
  }

  List<ApiChange> _changed(String id, SnapshotType old, SnapshotType now) {
    if (old.kind != now.kind) {
      return [
        ApiChange(
          .breaking,
          '${old.name} changed from a ${_kind(old.kind)} to a '
          '${_kind(now.kind)}.',
          type: id,
        ),
      ];
    }
    return [
      if (old.name != now.name)
        ApiChange(
          .breaking,
          '${_label(old)} ${old.name} was renamed to ${now.name}.',
          type: id,
        ),
      ?_sealing(id, old, now),
      for (final fact in {...old.facts.keys, ...now.facts.keys})
        if (old.facts[fact] != now.facts[fact])
          ApiChange(
            _facts.categoryOf(fact, old.facts[fact], now.facts[fact]),
            _facts.describe(now.name, fact, old.facts[fact], now.facts[fact]),
            type: id,
          ),
      ..._members.of(id, old, now),
    ];
  }

  /// The change of `exhaustive`: a sealed type that becomes an interface
  /// breaks a `switch` without a default, an interface that becomes sealed
  /// breaks a class that implements it.
  static ApiChange? _sealing(String id, SnapshotType old, SnapshotType now) =>
      switch ((old.exhaustive, now.exhaustive)) {
        (true, false) => ApiChange(
          .switchBreaking,
          '${now.name} is no longer sealed: a switch over it needs a default '
          'case.',
          type: id,
        ),
        (false, true) => ApiChange(
          .breaking,
          '${now.name} is now sealed: a class that implements it no longer '
          'compiles.',
          type: id,
        ),
        _ => null,
      };

  static String _label(SnapshotType type) {
    final kind = _kind(type.kind);
    return '${kind[0].toUpperCase()}${kind.substring(1)}';
  }

  static String _kind(TypeKind kind) => switch (kind) {
    .model => 'model',
    .enumeration => 'enum',
    .union => 'union',
    .statusType => 'status type',
    .eventUnion => 'event union',
    .parts => 'parts class',
    .group => 'API class',
    .root => 'root client',
  };
}
