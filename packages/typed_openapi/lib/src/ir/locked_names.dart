import '../diagnostics/message_text.dart';
import '../model/spec_node.dart';
import 'ir_context.dart';
import 'name_lock.dart';
import 'names.dart';
import 'pending_declaration.dart';
import 'spec_operation.dart';
import 'stream_successes.dart';

/// Claims the names the client's API lock keeps (M12, decision 5), so that
/// adding a schema or an operation never renames a type or a method that
/// existed, and reports where the lock decided: TOA569, TOA570, TOA571.
final class LockedNames {
  /// Claims names for the client of [_context].
  const LockedNames(this._context);

  final IrContext _context;

  NameLock get _lock => _context.names;

  /// Keeps in the library [scope] the names of the declarations [pending];
  /// a type of the lock that is not among them is released (TOA571), and a
  /// name that is not a usable type name is not kept (TOA569).
  void lockTypes(NameScope scope, Iterable<PendingDeclaration> pending) {
    final sites = <String, SpecLocation>{};
    for (final declaration in pending) {
      if (_lock.typeKey(declaration.id) case final key?) {
        sites[key] = declaration.id.location;
      }
    }
    _keep(scope, .type, 'this type', {
      for (final MapEntry(:key, :value) in sites.entries)
        if (_lock.types[key] case final name?) key: (name, value),
    });
    for (final MapEntry(:key, :value) in _lock.types.entries) {
      if (sites.containsKey(key)) continue;
      _context.report(
        .lockedNameReleased,
        'typed_openapi.lock keeps the name ${MessageText.quote(value)} for '
        'the schema at ${MessageText.quote(key)}, which this run does not '
        'declare; the name is free again.',
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
  /// [entries] and of their event-stream methods; a name that is not a
  /// usable method name is not kept (TOA569).
  void lockMethods(NameScope scope, Iterable<SpecOperation> entries) {
    final kept = <String, (String, SpecLocation)>{};
    for (final entry in entries) {
      final hasStream = StreamSuccesses.of(
        _context,
        entry.operation,
      ).streams.isNotEmpty;
      for (final isStream in [false, if (hasStream) true]) {
        final key = _methodKey(entry, isStream: isStream);
        if (_lock.methods[key] case final name?) {
          kept[key] = (name, entry.operation.location);
        }
      }
    }
    _keep(scope, .member, 'this method', kept);
  }

  /// Locks the names of [kept] (identity to name and site) that are valid
  /// for [kind] and not reserved in [scope]; reports the others.
  void _keep(
    NameScope scope,
    NameKind kind,
    String what,
    Map<String, (String, SpecLocation)> kept,
  ) {
    const names = DartNames();
    final usable = <String, String>{};
    final unusable = <String>{};
    for (final MapEntry(:key, value: (name, _)) in kept.entries) {
      if (names.isValid(name, kind)) {
        usable[key] = name;
      } else {
        unusable.add(key);
      }
    }
    unusable.addAll(scope.lock(usable).keys);
    for (final key in unusable) {
      final (name, site) = kept[key]!;
      _context.report(
        .lockedNameTaken,
        'typed_openapi.lock keeps the name ${MessageText.quote(name)} for '
        '$what, which is not a usable Dart name here; it is named anew.',
        site,
        fix: 'Run generate --fresh-names to write new names to the lock.',
      );
    }
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
          'typed_openapi.lock keeps the name ${MessageText.quote(name)} of '
          '$what; without the lock it would be named '
          '${MessageText.quote(candidate)}.',
          at,
          fix: 'Run generate --fresh-names to take the new name.',
        );
        return (name, null);
      case .lockTaken:
        _context.report(
          .lockedNameTaken,
          'typed_openapi.lock keeps the name ${MessageText.quote(kept ?? '')} '
          'for $what, but another name of the library has it first (an '
          "override's name, a custom type or another entry of the lock); it "
          'is named ${MessageText.quote(name)}.',
          at,
          fix: 'Rename the override or the custom type to keep the name.',
        );
        return (name, null);
      case .reserved || .collision || null:
        return claimed;
    }
  }
}
