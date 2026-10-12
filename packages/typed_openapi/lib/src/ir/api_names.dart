import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';

/// Names the types the API emitter declares (M9) in the library scope, after
/// the declarations, the groups and the types M8 adds, so that a model or
/// a group is never renamed by them: the root client, then for each
/// operation (groups and operations by name) the sealed type of its
/// successes and its variants, the sealed type of its errors and its
/// variants, and the class of its multipart parts. A sealed type is
/// `<Operation>Response` or `<Operation>Error`, or the plural when an
/// inline body has that name; any other change is reported (TOA550,
/// TOA551).
final class ApiNames {
  /// Creates the namer for [_context], claiming in the library scope
  /// [_types].
  ApiNames(this._context, this._types);

  static const _names = DartNames();

  /// The HTTP reason phrases of the statuses with a registered meaning, as
  /// variant names (RFC 9110 and the earlier names it renamed, such as
  /// `UnprocessableEntity`).
  static const reasons = {
    100: 'Continue', 101: 'SwitchingProtocols', 102: 'Processing', //
    103: 'EarlyHints', 200: 'Ok', 201: 'Created', 202: 'Accepted',
    203: 'NonAuthoritativeInformation', 204: 'NoContent',
    205: 'ResetContent', 206: 'PartialContent', 207: 'MultiStatus',
    208: 'AlreadyReported', 226: 'ImUsed', 300: 'MultipleChoices',
    301: 'MovedPermanently', 302: 'Found', 303: 'SeeOther',
    304: 'NotModified', 305: 'UseProxy', 307: 'TemporaryRedirect',
    308: 'PermanentRedirect', 400: 'BadRequest', 401: 'Unauthorized',
    402: 'PaymentRequired', 403: 'Forbidden', 404: 'NotFound',
    405: 'MethodNotAllowed', 406: 'NotAcceptable',
    407: 'ProxyAuthenticationRequired', 408: 'RequestTimeout',
    409: 'Conflict', 410: 'Gone', 411: 'LengthRequired',
    412: 'PreconditionFailed', 413: 'PayloadTooLarge', 414: 'UriTooLong',
    415: 'UnsupportedMediaType', 416: 'RangeNotSatisfiable',
    417: 'ExpectationFailed', 421: 'MisdirectedRequest',
    422: 'UnprocessableEntity', 423: 'Locked', 424: 'FailedDependency',
    425: 'TooEarly', 426: 'UpgradeRequired', 428: 'PreconditionRequired',
    429: 'TooManyRequests', 431: 'RequestHeaderFieldsTooLarge',
    451: 'UnavailableForLegalReasons', 500: 'InternalServerError',
    501: 'NotImplemented', 502: 'BadGateway', 503: 'ServiceUnavailable',
    504: 'GatewayTimeout', 505: 'HttpVersionNotSupported',
    506: 'VariantAlsoNegotiates', 507: 'InsufficientStorage',
    508: 'LoopDetected', 510: 'NotExtended',
    511: 'NetworkAuthenticationRequired',
  };

  /// The names of status ranges.
  static const ranges = {
    '1': 'Informational', '2': 'Success', '3': 'Redirection', //
    '4': 'ClientError', '5': 'ServerError',
  };

  final IrContext _context;
  final NameScope _types;

  /// The variant name of [status]: the reason phrase of a code, the name of
  /// a range (`4XX` is `ClientError`), `Other` for `default`, and `Status`
  /// with the code for a code without a registered meaning (`Status499`).
  static String variantOf(String status) {
    if (status == 'default') return 'Other';
    final code = int.tryParse(status);
    if (code != null) return reasons[code] ?? 'Status$status';
    if (status.length == 3 && status.substring(1).toUpperCase() == 'XX') {
      final range = ranges[status[0]];
      if (range != null) return range;
    }
    return 'Status${status.toUpperCase().replaceAll(_notAlphanumeric, '')}';
  }

  static final _notAlphanumeric = RegExp('[^0-9A-Z]');

  /// The IR of the client: [declarations] and the groups by their word
  /// ([groups], the tag or path segment in UpperCamelCase, `''` for the
  /// default group), with the root client, the fields of the groups in it
  /// and the servers, and the types of every operation named.
  ClientIr client(
    List<Declaration> declarations,
    Map<String, GroupIr> groups,
  ) {
    final root = this.root();
    // The root client's members: a field per group, then the servers.
    final members = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
      reservedSuffix: '_',
    );
    final defaultGroup = _context.config.defaultGroup;
    return ClientIr(
      declarations: declarations,
      groups: [
        for (final MapEntry(key: word, value: group) in groups.entries)
          GroupIr(
            group.name,
            [for (final operation in group.operations) name(operation)],
            field: members
                .claim(
                  _names.camel(word.isEmpty ? defaultGroup : word) ?? 'api',
                )
                .$1,
          ),
      ],
      root: RootIr(root, servers: servers(members)),
    );
  }

  /// The root client class: `naming.client`, else the client's name in
  /// UpperCamelCase with `Client`.
  String root() {
    final candidate =
        _context.config.clientClass ??
        '${_names.pascal(_context.client.name) ?? 'Api'}Client';
    return _claim(
      candidate,
      'the root client',
      SpecLocation(
        _context.model.document.location.document,
        JsonPointer.root,
      ),
      fix: 'Set naming.client in the config.',
    );
  }

  /// [operation] with the names of the types the emitter declares for it.
  OperationIr name(OperationIr operation) {
    final prefix = _names.pascal(operation.name) ?? 'Operation';
    final bodies = {for (final s in operation.successes) s.type};
    final successType = bodies.length > 1
        ? _statusType(
            operation,
            '${prefix}Response',
            [for (final s in operation.successes) (s.status, s.type)],
            'successes',
            {
              for (final s in operation.successes)
                if (s.sensitive) s.status,
            },
          )
        : null;
    final errorType = switch (operation.errors) {
      ErrorsByStatus(:final cases, :final sensitive) => _statusType(
        operation,
        '${prefix}Error',
        cases,
        'errors',
        sensitive,
      ),
      _ => null,
    };
    final partsName = operation.body?.parts == null
        ? null
        : _claim(
            '${prefix}Request',
            'the class of the parts of ${operation.name}',
            operation.location,
            override: operation,
          );
    return operation.withTypes(
      successType: successType,
      errorType: errorType,
      partsName: partsName,
    );
  }

  StatusTypeIr _statusType(
    OperationIr operation,
    String candidate,
    List<(String, DartType?)> cases,
    String what,
    Set<String> sensitive,
  ) {
    // The one body of the operation's successes or errors may have the
    // name already (an inline schema of one 2xx or one error response is
    // `GetPetResponse` or `GetPetError`): the plural is the documented
    // second choice.
    final plural = '${candidate}s';
    final name = _claim(
      _types.isTaken(candidate) && !_types.isTaken(plural) ? plural : candidate,
      'the sealed type of the $what of ${operation.name}',
      operation.location,
      override: operation,
    );
    return StatusTypeIr(name, [
      for (final (status, type) in cases)
        StatusCaseIr(
          status,
          _claim(
            '$name${variantOf(status)}',
            'the variant of $status',
            operation.location,
            override: operation,
          ),
          type,
          sensitive: sensitive.contains(status),
        ),
    ]);
  }

  /// Claims [candidate] for [what] in the library scope; a name that
  /// differs is reported at [at], with an override of the operation's name
  /// when [override] is given.
  String _claim(
    String candidate,
    String what,
    SpecLocation at, {
    OperationIr? override,
    String? fix,
  }) {
    final (name, change) = _types.claim(candidate);
    if (change == null) return name;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? '"$candidate" is a name Dart already has; $what is named "$name".'
          : 'Another type is named "$candidate"; $what is named "$name".',
      at,
      fix:
          fix ??
          'Rename the other type, or name the operation explicitly: its '
              'name starts the name of the type.',
      override: override == null
          ? null
          : _context.overrideAt(
              ['operations', override.overrideKey],
              {'name': override.name},
            ),
    );
    return name;
  }

  /// The servers of the document as members of the root client, claimed
  /// in [members] after the group fields: `server` for one, `server1`,
  /// `server2`, ... for several.
  List<ServerIr> servers(NameScope members) {
    final servers = _context.model.document.servers;
    return [
      for (final (i, server) in servers.indexed)
        if (server.url case final url?)
          ServerIr(
            name: members
                .claim(servers.length == 1 ? 'server' : 'server${i + 1}')
                .$1,
            url: url,
            location: server.location,
            description: server.description,
            variables: _serverVariables(server.variables),
          ),
    ];
  }

  static List<ServerVariableIr> _serverVariables(
    Map<String, ServerVariable> variables,
  ) {
    final scope = NameScope(
      reserved: DartNames.reservedWords,
      reservedSuffix: '_',
    );
    return [
      for (final MapEntry(key: wire, :value) in variables.entries)
        ServerVariableIr(
          name: scope.claim(_names.camel(wire) ?? 'value').$1,
          wireName: wire,
          defaultValue: value.defaultValue,
          values: value.enumValues ?? const [],
          description: value.description,
        ),
    ];
  }
}
