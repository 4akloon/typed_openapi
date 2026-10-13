import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'type_claims.dart';

/// Names the root client (M9): its class and its members, the field of each
/// group and the servers, and the arguments of a server's variables.
final class RootNames {
  /// Creates the namer; it claims the class with [_claims].
  RootNames(this._context, this._claims)
    : members = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
        reservedSuffix: '_',
      );

  static const _names = DartNames();

  final IrContext _context;
  final TypeClaims _claims;

  /// The members of the root client: a field per group, then the servers.
  final NameScope members;

  /// The root client class: `naming.client`, else the client's name in
  /// UpperCamelCase with `Client`. A client name that loses letters (TOA559)
  /// or has none (TOA552) is reported; one that starts with a digit gets the
  /// prefix `Api`, as a class name cannot start with one.
  String root() {
    final at = SpecLocation(
      _context.model.document.location.document,
      JsonPointer.root,
    );
    return _claims.claim(
      _context.config.clientClass ?? _fromClientName(at),
      'the root client',
      at,
      fix: 'Set naming.client in the config.',
    );
  }

  String _fromClientName(SpecLocation at) {
    final source = _context.client.name;
    final pascal = _names.pascal(source);
    if (pascal == null) {
      _reportUnnamed(source, at);
      return 'ApiClient';
    }
    final isPrefixed = pascal.startsWith(r'$');
    final name = isPrefixed ? 'Api${pascal.substring(1)}' : pascal;
    if (isPrefixed) {
      _context.report(
        .nameLossy,
        'The client name "$source" starts with a digit, which a class name '
        'cannot; the root client is named "${name}Client".',
        at,
        fix: 'Set naming.client in the config.',
      );
    }
    _context.checkLossyName(
      source,
      '${name}Client',
      at,
      what: 'The client name',
      fix: 'Set naming.client in the config.',
    );
    return '${name}Client';
  }

  /// Reports a client name that gave no word: letters were lost (TOA559) or
  /// there were none (TOA552).
  void _reportUnnamed(String source, SpecLocation at) {
    const fix = 'Set naming.client in the config.';
    if (_names.dropsLetters(source)) {
      _context.checkLossyName(
        source,
        'ApiClient',
        at,
        what: 'The client name',
        fix: fix,
      );
      return;
    }
    _context.report(
      .nameUnrepresentable,
      'The client name "$source" has no ASCII letter or digit; the root '
      'client is named "ApiClient".',
      at,
      fix: fix,
    );
  }

  /// The field of the group [group] in the root client, from [word] (its tag
  /// or path segment); a name that is changed is reported at [at].
  String groupField(String word, GroupIr group, SpecLocation at) {
    final candidate =
        _names.camel(word.isEmpty ? _context.config.defaultGroup : word) ??
        'api';
    final (name, change) = members.claim(candidate);
    _reportMember(change, candidate, name, 'the field of ${group.name}', at);
    return name;
  }

  /// The servers of the document as members of the root client, claimed
  /// after the group fields: `server` for one, `server1`, `server2`, ...
  /// for several.
  List<ServerIr> servers() {
    final servers = _context.model.document.servers;
    return [
      for (final (i, server) in servers.indexed)
        if (server.url case final url?)
          ServerIr(
            name: _serverName(
              servers.length == 1 ? 'server' : 'server${i + 1}',
              server,
            ),
            url: url,
            location: server.location,
            description: server.description,
            variables: _serverVariables(server),
          ),
    ];
  }

  String _serverName(String candidate, Server server) {
    final (name, change) = members.claim(candidate);
    _reportMember(
      change,
      candidate,
      name,
      'the server method',
      server.location,
    );
    return name;
  }

  void _reportMember(
    NameChange? change,
    String candidate,
    String name,
    String what,
    SpecLocation at,
  ) {
    if (change == null) return;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? '"$candidate" is a name Dart already has; $what of the root '
                'client is named "$name".'
          : 'Another member of the root client is named "$candidate"; $what '
                'is named "$name".',
      at,
      fix: 'Rename the tag or the server at the source.',
    );
  }

  List<ServerVariableIr> _serverVariables(Server server) {
    final scope = NameScope(
      reserved: DartNames.reservedWords,
      reservedSuffix: '_',
    );
    return [
      for (final MapEntry(key: wire, :value) in server.variables.entries)
        ServerVariableIr(
          name: _claimVariable(scope, wire, value.location),
          wireName: wire,
          defaultValue: value.defaultValue,
          values: value.enumValues ?? const [],
          description: value.description,
        ),
    ];
  }

  /// The argument name of the server variable [wire], reported when it is
  /// not the name the variable makes (TOA550, TOA551, TOA552, TOA559).
  String _claimVariable(NameScope scope, String wire, SpecLocation at) {
    final automatic = _names.camel(wire);
    final candidate = automatic ?? 'value';
    final (name, change) = scope.claim(candidate);
    const fix =
        'Rename the variable at the source; the URL still uses its own '
        'name.';
    if (automatic == null) {
      _context.report(
        .nameUnrepresentable,
        'Server variable "$wire" has no ASCII letter or digit; the argument '
        'is named "$name".',
        at,
        fix: fix,
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Server variable "$wire" would be the Dart name "$candidate"; '
                  'the argument is named "$name".'
            : 'Another server variable is named "$candidate"; the argument '
                  'of "$wire" is named "$name".',
        at,
        fix: fix,
      );
    }
    if (automatic != null) {
      _context.checkLossyName(
        wire,
        name,
        at,
        what: 'Server variable',
        fix: fix,
      );
    }
    return name;
  }
}
