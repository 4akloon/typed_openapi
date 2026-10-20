import '../snapshot/api_snapshot.dart';
import 'api_change.dart';
import 'fact_changes.dart';

/// The changes of the members of a type that both snapshots have.
final class MemberChanges {
  /// Creates the comparer.
  const MemberChanges();

  static const _facts = FactChanges();

  /// The changes from [before] to [after], the type [id] in both
  /// snapshots.
  List<ApiChange> of(String id, SnapshotType before, SnapshotType after) {
    final old = before.members;
    final now = after.members;
    return [
      for (final key in old.keys)
        if (!now.containsKey(key) && !_ownerGone(old[key]!, now))
          ApiChange(
            .breaking,
            '${_label(old[key]!)} ${_what(before, old[key]!)} was removed.',
            type: id,
            member: key,
          ),
      for (final key in now.keys)
        if (!old.containsKey(key) && !_ownerGone(now[key]!, old))
          ApiChange(
            _added(now[key]!, after),
            '${_label(now[key]!)} ${_what(after, now[key]!)} was added.',
            type: id,
            member: key,
          ),
      for (final key in old.keys)
        if (now[key] case final member?)
          ..._changed(id, key, (before, old[key]!), (after, member)),
    ];
  }

  /// Whether [member] belongs to a member [others] does not have: a
  /// parameter of a method that was added or removed is part of that
  /// change.
  static bool _ownerGone(
    SnapshotMember member,
    Map<String, SnapshotMember> others,
  ) => member.owner != null && !others.containsKey(member.owner);

  /// The category of the new [member] of [type]: a required field or
  /// argument breaks, a new value, variant, case or event breaks an
  /// exhaustive `switch`, anything else is additive.
  static ChangeCategory _added(SnapshotMember member, SnapshotType type) =>
      switch (member.kind) {
        .field ||
        .parameter ||
        .body when member.facts['required'] == 'true' => .breaking,
        .value ||
        .variant ||
        .statusCase ||
        .event when type.exhaustive => .switchBreaking,
        _ => .additive,
      };

  List<ApiChange> _changed(
    String id,
    String key,
    (SnapshotType, SnapshotMember) before,
    (SnapshotType, SnapshotMember) after,
  ) {
    final (oldType, old) = before;
    final (newType, now) = after;
    final what = '${_label(now)} ${_what(newType, now)}';
    return [
      if (old.name != now.name)
        ApiChange(
          .breaking,
          '${_label(old)} ${_what(oldType, old)} was renamed to ${now.name}.',
          type: id,
          member: key,
        ),
      for (final fact in {...old.facts.keys, ...now.facts.keys})
        if (old.facts[fact] != now.facts[fact])
          ApiChange(
            _facts.categoryOf(fact, old.facts[fact], now.facts[fact]),
            _facts.describe(what, fact, old.facts[fact], now.facts[fact]),
            type: id,
            member: key,
          ),
    ];
  }

  /// [member] of [type] as code names it: `Pet.name`, or
  /// `PetsApi.listPets(limit)` for an argument.
  static String _what(SnapshotType type, SnapshotMember member) {
    final owner = type.members[member.owner]?.name;
    return owner == null
        ? '${type.name}.${member.name}'
        : '${type.name}.$owner(${member.name})';
  }

  static String _label(SnapshotMember member) => switch (member.kind) {
    .field => 'Field',
    .value => 'Enum value',
    .variant => 'Union variant',
    .statusCase => 'Status variant',
    .event => 'Event variant',
    .method => 'Method',
    .parameter => 'Argument',
    .body => 'Argument',
    .groupField => 'Field',
    .server => 'Server',
  };
}
