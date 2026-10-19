/// Why [NameScope.claim] did not give the candidate itself.
enum NameChange {
  /// The candidate is a reserved word or a name Dart already has.
  reserved,

  /// Another declaration of the scope already has the candidate.
  collision,

  /// The API lock keeps the name the identity had, which is not the
  /// candidate (M12, decision 5).
  kept,

  /// The API lock keeps a name for the identity, but an explicit name (an
  /// override's, or a type of the user) took it first.
  lockTaken,
}

/// The names of one scope (a library's types, a class's members, a
/// method's arguments), given out in the order they are claimed.
///
/// Callers claim in a deterministic order (by spec location), so the same
/// spec always gives the same names. With [lock], a claim for an identity
/// gets the name the API lock keeps for it, and no other claim but an
/// explicit one takes that name.
final class NameScope {
  /// Creates a scope where [reserved] names get [reservedSuffix].
  NameScope({required Set<String> reserved, required this.reservedSuffix})
    : _reserved = reserved;

  final Set<String> _reserved;
  final Set<String> _taken = {};
  final Map<String, String> _kept = {};
  final Map<String, String> _keeper = {};

  /// What a reserved name gets appended: `Model` for types, `_` for
  /// members.
  final String reservedSuffix;

  /// Whether [name] is given out.
  bool isTaken(String name) => _taken.contains(name);

  /// The names given out so far, as a snapshot.
  Set<String> get taken => {..._taken};

  /// Gives [name] to something that is not named in this scope (a type the
  /// user's code declares), so that a later claim of it is a collision.
  void reserve(String name) => _taken.add(name);

  /// Keeps each name of [names] for its identity, the key: only a claim
  /// for that identity, or an explicit one, gets it. Lock only the
  /// identities that are claimed in this run, so a name whose owner is
  /// gone is free again. A name that is reserved here is not kept; those
  /// entries are returned.
  Map<String, String> lock(Map<String, String> names) {
    final rejected = <String, String>{};
    for (final MapEntry(key: identity, value: name) in names.entries) {
      if (_reserved.contains(name)) {
        rejected[identity] = name;
        continue;
      }
      _kept[identity] = name;
      _keeper[name] = identity;
    }
    return rejected;
  }

  /// Gives out [candidate], or a free name made from it: with
  /// [reservedSuffix] when it is reserved, then the first free of
  /// [alternatives], then with `2`, `3`, ... appended. Returns the name and
  /// why it differs from [candidate], if it does.
  ///
  /// A claim for [identity] gets the name [lock] keeps for it while that is
  /// free ([NameChange.kept] when it is not [candidate] for another
  /// reason); an [isExplicit] claim (an override's name) ignores the lock
  /// and may take a name it keeps for another identity.
  (String, NameChange?) claim(
    String candidate, {
    List<String> alternatives = const [],
    String? identity,
    bool isExplicit = false,
  }) {
    if (isExplicit && identity != null) _release(identity);
    final kept = isExplicit ? null : _kept[identity];
    if (kept != null && _taken.add(kept)) {
      return (kept, _keptChange(candidate, kept, identity));
    }
    final owner = isExplicit ? null : identity ?? '';
    final (name, change) = _claim(candidate, alternatives, owner);
    return (name, kept == null ? change : .lockTaken);
  }

  /// Frees the name kept for [identity], which an explicit name replaces.
  void _release(String identity) {
    final name = _kept.remove(identity);
    if (name != null && _keeper[name] == identity) _keeper.remove(name);
  }

  /// Why the [kept] name of [identity] is not [candidate]: what a run
  /// without the lock would report, else [NameChange.kept].
  NameChange? _keptChange(String candidate, String kept, String? identity) {
    if (kept == candidate) return null;
    if (_reserved.contains(candidate)) return .reserved;
    final keeper = _keeper[candidate];
    if (_taken.contains(candidate) || (keeper != null && keeper != identity)) {
      return .collision;
    }
    return .kept;
  }

  /// [candidate] or a free name made from it for [owner]: null for an
  /// explicit claim, which may take any name not given out.
  (String, NameChange?) _claim(
    String candidate,
    List<String> alternatives,
    String? owner,
  ) {
    if (_reserved.contains(candidate)) {
      return (_free('$candidate$reservedSuffix', owner), .reserved);
    }
    if (_take(candidate, owner)) return (candidate, null);
    for (final alternative in alternatives) {
      if (!_reserved.contains(alternative) && _take(alternative, owner)) {
        return (alternative, .collision);
      }
    }
    return (_free(candidate, owner), .collision);
  }

  String _free(String base, String? owner) {
    if (_take(base, owner)) return base;
    for (var i = 2; ; i++) {
      if (_take('$base$i', owner)) return '$base$i';
    }
  }

  /// Gives [name] to [owner] unless it is given out or kept for another
  /// identity.
  bool _take(String name, String? owner) {
    final keeper = _keeper[name];
    if (owner != null && keeper != null && keeper != owner) return false;
    return _taken.add(name);
  }
}
