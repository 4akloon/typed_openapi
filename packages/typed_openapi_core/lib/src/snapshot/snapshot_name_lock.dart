import '../ir/name_lock.dart';
import 'api_snapshot.dart';

/// The [NameLock] an [ApiSnapshot] holds (M12, decision 5): the name of
/// every model, enum and union by its identity, and of every method by its
/// operation's `METHOD /path`.
final class SnapshotNameLock {
  const SnapshotNameLock._();

  static const _stream = '#stream';

  /// The names [snapshot], made for the spec whose root document is
  /// [root], keeps.
  static NameLock of(ApiSnapshot snapshot, Uri root) {
    final types = <String, String>{};
    final methods = <String, String>{};
    for (final MapEntry(key: id, value: type) in snapshot.types.entries) {
      if (_isDeclaration(type.kind)) types[id] = type.name;
      for (final MapEntry(key: memberId, value: member)
          in type.members.entries) {
        if (_methodKey(type, memberId, member) case final key?) {
          methods[key] = member.name;
        }
      }
    }
    return NameLock(root: root, types: types, methods: methods);
  }

  static bool _isDeclaration(TypeKind kind) => switch (kind) {
    .model || .enumeration || .union => true,
    _ => false,
  };

  /// The lock key of the method [member] of [group]; the events method of
  /// an operation that has no other method is its operation's one method.
  static String? _methodKey(
    SnapshotType group,
    String id,
    SnapshotMember member,
  ) {
    if (member.kind != .method) return null;
    final (method, path) = (member.facts['method'], member.facts['path']);
    if (method == null || path == null) return null;
    final isSecond =
        id.endsWith(_stream) &&
        group.members.containsKey(id.substring(0, id.length - _stream.length));
    return NameLock.methodKey(method, path, isStream: isSecond);
  }
}
