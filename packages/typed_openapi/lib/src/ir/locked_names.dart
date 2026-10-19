import '../model/spec_node.dart';
import 'ir_context.dart';
import 'name_lock.dart';
import 'names.dart';
import 'pending_declaration.dart';
import 'spec_operation.dart';

/// Claims the names the client's API lock keeps (M12, decision 5), so that
/// adding a schema or an operation never renames a type or a method that
/// existed, and reports where the lock decided: TOA569, TOA570, TOA571.
final class LockedNames {
  /// Claims names for the client of [_context].
  const LockedNames(this._context);

  final IrContext _context;

  NameLock get _lock => _context.names;

  /// Keeps in the library [scope] the names of the declarations [pending];
  /// a type of the lock that is not among them is released (TOA571).
  void lockTypes(NameScope scope, Iterable<PendingDeclaration> pending) {
    final present = {
      for (final declaration in pending) ?_lock.typeKey(declaration.id),
    };
    scope.lock({for (final key in present) key: ?_lock.types[key]});
    for (final MapEntry(:key, :value) in _lock.types.entries) {
      if (present.contains(key)) continue;
      _context.report(
        .lockedNameReleased,
        'typed_openapi.lock keeps the name "$value" for the schema at '
        '"$key", which this run does not declare; the name is free again.',
        _context.model.document.location,
      );
    }
  }

  /// Claims [candidate] in [scope] for the declaration [pending], or the
  /// name the lock keeps for it. A change the lock made is reported and
  /// returned as none.
  (String, NameChange?) claimType(
    NameScope scope,
    PendingDeclaration pending,
    String candidate,
  ) {
    final identity = _lock.typeKey(pending.id);
    final claimed = scope.claim(
      candidate,
      identity: identity,
      isExplicit: pending.overrideName != null,
    );
    return _reported(claimed, candidate, _lock.types[identity], (
      'this type',
      pending.id.location,
    ));
  }

  /// Keeps in a group's method [scope] the names of the operations
  /// [entries] and of their event-stream methods.
  void lockMethods(NameScope scope, Iterable<SpecOperation> entries) {
    scope.lock({
      for (final entry in entries)
        for (final isStream in const [false, true])
          _methodKey(entry, isStream: isStream):
              ?_lock.methods[_methodKey(entry, isStream: isStream)],
    });
  }

  /// Claims [candidate] in [scope] for the method of [entry], its
  /// event-stream method when [isStream], or the name the lock keeps for
  /// it; an [isExplicit] claim (an override's name) ignores the lock. A
  /// change the lock made is reported and returned as none.
  (String, NameChange?) claimMethod(
    NameScope scope,
    SpecOperation entry,
    String candidate, {
    required bool isStream,
    bool isExplicit = false,
  }) {
    final identity = _methodKey(entry, isStream: isStream);
    final claimed = scope.claim(
      candidate,
      identity: identity,
      isExplicit: isExplicit,
    );
    return _reported(claimed, candidate, _lock.methods[identity], (
      'the ${isStream ? 'event-stream ' : ''}method of ${entry.overrideKey}',
      entry.operation.location,
    ));
  }

  static String _methodKey(SpecOperation entry, {required bool isStream}) =>
      NameLock.methodKey(entry.method, entry.path, isStream: isStream);

  /// [claimed], with a change the lock made reported (the [kept] name of
  /// what the [site] names) and returned as none.
  (String, NameChange?) _reported(
    (String, NameChange?) claimed,
    String candidate,
    String? kept,
    (String, SpecLocation) site,
  ) {
    final (name, change) = claimed;
    final (what, at) = site;
    switch (change) {
      case .kept:
        _context.report(
          .lockedNameKept,
          'typed_openapi.lock keeps the name "$name" of $what; without the '
          'lock it would be named "$candidate".',
          at,
          fix: 'Run generate --fresh-names to take the new name.',
        );
        return (name, null);
      case .lockTaken:
        _context.report(
          .lockedNameTaken,
          'typed_openapi.lock keeps the name "$kept" for $what, but an '
          "override's name or a custom type has it; it is named \"$name\".",
          at,
          fix: 'Rename the override or the custom type to keep the name.',
        );
        return (name, null);
      case .reserved || .collision || null:
        return claimed;
    }
  }
}
