import '../model/path_template.dart';
import 'ir_context.dart';
import 'locked_names.dart';
import 'names.dart';
import 'spec_operation.dart';

/// Names the methods of a group class (R5.1): an override's name, else
/// `operationId` without the configured prefix, else a name made from the
/// method and the path, in lowerCamelCase.
final class MethodNames {
  /// Creates the namer for the client of [_context].
  const MethodNames(this._context);

  static const _names = DartNames();

  /// The `operationId` prefix the `nestjs` preset removes:
  /// `UserController_get` → `get`.
  static final nestjsPrefix = RegExp('^[A-Za-z0-9]*Controller_');

  final IrContext _context;

  LockedNames get _locked => LockedNames(_context);

  /// The method names of the operations [entries] of one group, in
  /// [scope]. Names that overrides give are claimed first, so an automatic
  /// name that is the same gets the suffix, not the override's; the API
  /// lock's names win over the automatic ones (M12).
  Map<SpecOperation, String> of(
    List<SpecOperation> entries,
    NameScope scope,
  ) {
    _locked.lockMethods(scope, entries);
    final overrides = <SpecOperation, String>{};
    for (final entry in entries) {
      final override = _context.overrides.operationAt(entry.operation.location);
      final name = override?.name;
      if (override == null || name == null) continue;
      final checked = _context.checkedOverrideName(
        override,
        'name',
        name,
        .member,
        what: 'method',
      );
      if (checked != null) overrides[entry] = checked;
    }
    final names = <SpecOperation, String>{};
    for (final entry in [
      for (final e in entries)
        if (overrides.containsKey(e)) e,
      for (final e in entries)
        if (!overrides.containsKey(e)) e,
    ]) {
      names[entry] = _methodName(entry, scope, overrides[entry]);
    }
    return names;
  }

  /// The method name of [entry] in its group's [scope]: [override], else
  /// `operationId` without the configured prefix, else [_pathName].
  String _methodName(SpecOperation entry, NameScope scope, String? override) {
    final operation = entry.operation;
    final prefix =
        _context.config.operationPrefix ??
        (_context.client.preset == .nestjs ? nestjsPrefix : null);
    final id = operation.operationId;
    final source = id == null
        ? _pathName(entry.method, entry.path)
        : prefix == null
        ? id
        : _withoutPrefix(id, prefix);
    final candidate = override ?? _names.camel(source);
    final (name, change) = _locked.claimMethod(
      scope,
      entry,
      candidate ?? 'operation',
      isStream: false,
      isExplicit: override != null,
    );
    final at = ['operations', entry.overrideKey];
    if (candidate == null || change != null) {
      _reportChange(entry, candidate, (name, change));
    }
    if (override == null && candidate != null) {
      _context.checkLossyName(
        id == null ? entry.path : source,
        name,
        operation.location,
        what: id == null ? 'Path' : 'operationId',
        override: _context.overrideAt(at, {'name': name}),
      );
    }
    return name;
  }

  /// Reports that [entry]'s method is named `claimed.$1`, not [candidate]
  /// (null when the `operationId` has no ASCII letter or digit).
  void _reportChange(
    SpecOperation entry,
    String? candidate,
    (String, NameChange?) claimed,
  ) {
    final (name, change) = claimed;
    final id = entry.operation.operationId;
    _context.report(
      candidate == null
          ? .nameUnrepresentable
          : change == .reserved
          ? .nameReserved
          : .nameCollision,
      candidate == null
          ? 'operationId "$id" has no ASCII letter or digit; the method is '
                'named "$name".'
          : change == .reserved
          ? 'Method "$candidate" would be a name Dart already has; it is '
                'named "$name".'
          : 'Another method of the group is named "$candidate"; this one '
                'is named "$name".',
      entry.operation.location,
      fix: 'Name the method explicitly to keep the name stable.',
      override: _context.overrideAt(
        ['operations', entry.overrideKey],
        {'name': name},
      ),
    );
  }

  /// The words of a method name made from [method] and [path]: the method,
  /// the words of every path segment without its variables, then, when the
  /// path has variables, `By` and the variables in path order joined by
  /// `And`: `GET /users/{userId}/posts/{postId}` gives
  /// `getUsersPostsByUserIdAndPostId`, `GET /pets/{id}` gives
  /// `getPetsById`.
  static String _pathName(String method, String path) {
    final variables = [
      for (final match in PathTemplate(path).variables) match[1]!,
    ];
    final literal = path.replaceAll(PathTemplate.variable, ' ');
    if (variables.isEmpty) return '$method $literal';
    return '$method $literal By ${variables.join(' And ')}';
  }

  /// [id] without the match of [prefix] when it starts at index 0 and is
  /// not empty; else [id] itself.
  static String _withoutPrefix(String id, RegExp prefix) {
    final match = prefix.matchAsPrefix(id);
    if (match == null || match.end == 0) return id;
    return id.substring(match.end);
  }
}
