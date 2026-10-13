import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'event_union_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'response_body_names.dart';
import 'root_names.dart';
import 'type_claims.dart';

/// Names the types the API emitter declares (M9) in the library scope, after
/// the declarations, the groups and the types M8 adds, so that a model or
/// a group is never renamed by them: the root client, then for each
/// operation (groups and operations by name) the sealed type of its
/// successes and its variants, the sealed type of its errors and its
/// variants, and the class of its multipart parts. A sealed type is
/// `<Operation>Response` or `<Operation>Error`, or the plural when an
/// inline body of the operation itself has that name; any other change is
/// reported (TOA550, TOA551).
final class ApiNames {
  /// Creates the namer for [_context], claiming in the library scope
  /// [_types].
  ApiNames(IrContext context, NameScope types)
    : this._(context, TypeClaims(context, types));

  ApiNames._(this._context, this._claims)
    : _root = RootNames(_context, _claims),
      _events = EventUnionNames(_context, _claims);

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
  final TypeClaims _claims;
  final RootNames _root;
  final EventUnionNames _events;

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
    final root = _root.root();
    final inlineBodies = ResponseBodyNames(declarations);
    return ClientIr(
      declarations: declarations,
      groups: [
        for (final MapEntry(key: word, value: group) in groups.entries)
          GroupIr(
            group.name,
            [
              for (final operation in group.operations)
                name(operation, inlineBodies),
            ],
            field: _root.groupField(word, group, _locationOf(group)),
          ),
      ],
      root: RootIr(root, servers: _root.servers()),
    );
  }

  /// Where a problem of [group] is reported: its first operation, else the
  /// document.
  SpecLocation _locationOf(GroupIr group) =>
      group.operations.firstOrNull?.location ??
      SpecLocation(
        _context.model.document.location.document,
        JsonPointer.root,
      );

  /// [operation] with the names of the types the emitter declares for it;
  /// [inlineBodies] tells which names its own inline bodies have. A method
  /// that returns events has no sealed successes: it returns the stream.
  OperationIr name(OperationIr operation, ResponseBodyNames inlineBodies) {
    final prefix = _names.pascal(operation.name) ?? 'Operation';
    final bodies = {for (final s in operation.successes) s.type};
    final successType = bodies.length > 1 && operation.events == null
        ? _statusType(
            operation,
            _sealedName('${prefix}Response', operation, inlineBodies),
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
        _sealedName('${prefix}Error', operation, inlineBodies),
        cases,
        'errors',
        sensitive,
      ),
      _ => null,
    };
    final partsName = operation.body?.parts == null
        ? null
        : _claims.claim(
            '${prefix}Request',
            'the class of the parts of ${operation.name}',
            operation.location,
            override: operation,
          );
    return operation.withTypes(
      successType: successType,
      errorType: errorType,
      partsName: partsName,
      events: _events.name(operation, prefix),
    );
  }

  /// [candidate], or its plural when the inline body of [operation] has
  /// the name and the plural is free: the documented second choice.
  String _sealedName(
    String candidate,
    OperationIr operation,
    ResponseBodyNames inlineBodies,
  ) {
    final plural = '${candidate}s';
    return _claims.isTaken(candidate) &&
            !_claims.isTaken(plural) &&
            inlineBodies.isInlineBodyOf(operation, candidate)
        ? plural
        : candidate;
  }

  StatusTypeIr _statusType(
    OperationIr operation,
    String candidate,
    List<(String, DartType?)> cases,
    String what,
    Set<String> sensitive,
  ) {
    final name = _claims.claim(
      candidate,
      'the sealed type of the $what of ${operation.name}',
      operation.location,
      override: operation,
    );
    return StatusTypeIr(name, [
      for (final (status, type) in cases)
        StatusCaseIr(
          status,
          _claims.claim(
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
}
