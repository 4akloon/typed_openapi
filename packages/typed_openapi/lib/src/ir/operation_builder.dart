import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'body_encoding.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'operation_checks.dart';
import 'parts_builder.dart';
import 'response_secrets.dart';
import 'schema_defaults.dart';
import 'schema_mapper.dart';
import 'security_builder.dart';

/// An operation of the spec with its method and path.
final class SpecOperation {
  /// Creates the entry for [operation], found at [method] of [path].
  const SpecOperation(this.operation, this.method, this.path, this.item);

  /// The Operation Object.
  final Operation operation;

  /// The HTTP method as the spec writes it: lower case for the fixed
  /// fields, as written for OpenAPI 3.2 `additionalOperations`.
  final String method;

  /// The path template.
  final String path;

  /// The Path Item Object the operation is in.
  final PathItem item;

  /// The key of the operation in the overrides file: its `operationId`, or
  /// `METHOD /path`.
  String get overrideKey =>
      operation.operationId ?? '${method.toUpperCase()} $path';
}

/// Builds the IR of operations: parameters, bodies, responses and errors
/// (R10.3, R10.4, R10.6, R11.4); types come from a [SchemaMapper].
final class OperationBuilder {
  /// Creates a builder that maps types with [_mapper].
  OperationBuilder(this._context, this._mapper)
    : _checks = OperationChecks(_context),
      _security = SecurityBuilder(_context),
      _parts = PartsBuilder(_context, _mapper),
      _encoding = BodyEncoding(_context),
      _defaults = SchemaDefaults(_context),
      _secrets = ResponseSecrets(_context);

  static const _names = DartNames();

  /// A variable of a path template: `{name}`, where the name has no brace
  /// (`{}` is a variable with an empty name). The runtime resolves paths
  /// with the same pattern (`OperationRequest.pathVariable`), so every
  /// variable it finds has a parameter.
  static final pathVariable = RegExp(r'\{([^{}]*)\}');

  /// The header parameters OpenAPI says to ignore: the request's own
  /// `Accept`, `Content-Type` and `Authorization` (compared in lower case).
  static const _ignoredHeaders = {'accept', 'content-type', 'authorization'};

  /// The styles OpenAPI allows for each placement, the default style
  /// first (`style: cookie` is OpenAPI 3.2's second style for cookies); a
  /// `querystring` parameter has none.
  static const allowedStyles = {
    ParameterLocation.path: [
      ParameterStyle.simple,
      ParameterStyle.label,
      ParameterStyle.matrix,
    ],
    ParameterLocation.query: [
      ParameterStyle.form,
      ParameterStyle.spaceDelimited,
      ParameterStyle.pipeDelimited,
      ParameterStyle.deepObject,
    ],
    ParameterLocation.header: [ParameterStyle.simple],
    ParameterLocation.cookie: [ParameterStyle.form, ParameterStyle.cookie],
  };

  final IrContext _context;
  final SchemaMapper _mapper;
  final ResponseSecrets _secrets;
  final OperationChecks _checks;
  final SecurityBuilder _security;
  final PartsBuilder _parts;
  final BodyEncoding _encoding;
  final SchemaDefaults _defaults;

  /// How many operations [build] left out because a success is an event
  /// stream (TOA654).
  int streams = 0;

  /// How many operations [build] left out because a path variable has no
  /// parameter (TOA556).
  int unbound = 0;

  /// The IR of [entry], named [name]; null when its path template cannot
  /// be filled, or when a success is an event stream (counted in
  /// [streams]).
  OperationIr? build(SpecOperation entry, String name) {
    final operation = entry.operation;
    final prefix = _names.pascal(name) ?? name;
    final parameters = _parameters(entry, prefix);
    if (parameters == null) {
      unbound++;
      return null;
    }
    final responses = _responses(operation, prefix);
    if (_checks.isEventStream(responses)) {
      streams++;
      return null;
    }
    _checks.successes(operation);
    _checks.servers(entry);
    _checks.callbacks(operation);
    return OperationIr(
      location: operation.location,
      name: name,
      method: entry.method.toUpperCase(),
      path: entry.path,
      operationId: operation.operationId,
      tags: operation.tags,
      summary: operation.summary,
      description: operation.description,
      deprecated: operation.deprecated,
      parameters: parameters,
      body: _body(operation, entry.method, prefix),
      responses: responses,
      errors: _errors(responses),
      security: _security.of(operation),
    );
  }

  List<ParameterIr>? _parameters(SpecOperation entry, String prefix) {
    // Operation parameters replace path item parameters with the same name
    // and location.
    final byKey =
        <(ParameterLocation, String?), (ParameterLocation, Parameter)>{};
    for (final written in [
      ...entry.item.parameters,
      ...entry.operation.parameters,
    ]) {
      final parameter = _context.model.resolve(written);
      // A parameter without a valid `in` is not generated; the parser has
      // reported it (TOA111, TOA112).
      final placement = parameter?.placement;
      if (parameter == null || placement == null) continue;
      // OpenAPI says these headers SHALL be ignored: the HTTP client and
      // the body's media type decide them.
      if (placement == .header &&
          _ignoredHeaders.contains(parameter.name?.toLowerCase())) {
        continue;
      }
      byKey[(placement, parameter.name)] = (placement, parameter);
    }
    final variables = [
      for (final match in pathVariable.allMatches(entry.path)) match[1]!,
    ];
    var bound = true;
    for (final variable in variables) {
      if (byKey.containsKey((ParameterLocation.path, variable))) continue;
      bound = false;
      _context.report(
        .pathVariableUnbound,
        'Path variable "{$variable}" of ${entry.path} has no path parameter '
        'with this exact name, so the operation is not generated.',
        entry.operation.location,
        fix: 'Declare a path parameter named "$variable" at the source.',
      );
    }
    if (!bound) return null;
    final scope = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.argumentNames},
      reservedSuffix: '_',
    );
    const order = [
      ParameterLocation.path,
      ParameterLocation.query,
      ParameterLocation.querystring,
      ParameterLocation.header,
      ParameterLocation.cookie,
    ];
    // By location, then in the order of the spec (a sort is not stable).
    final sorted = byKey.values.toList().indexed.toList()
      ..sort((a, b) {
        final byPlacement = order.indexOf(a.$2.$1) - order.indexOf(b.$2.$1);
        return byPlacement != 0 ? byPlacement : a.$1 - b.$1;
      });
    final named = [
      for (final (_, (placement, parameter)) in sorted)
        if (parameter.name case final wire?)
          if (_isSendable(placement, parameter, wire))
            (placement, parameter, wire),
    ];
    // The names overrides give are claimed first, so an automatic name that
    // is the same gets the suffix, not the override's.
    final built = <int, ParameterIr>{};
    for (final withOverride in [true, false]) {
      for (final (i, (placement, parameter, wire)) in named.indexed) {
        final given =
            _context.overrides.parameterAt(parameter.location)?.name != null;
        if (given != withOverride) continue;
        built[i] = _parameter(entry, parameter, placement, wire, scope, prefix);
      }
    }
    return [for (var i = 0; i < named.length; i++) built[i]!];
  }

  /// Whether a parameter of [placement] can be sent; a `querystring`
  /// parameter cannot, and is reported (TOA565).
  bool _isSendable(
    ParameterLocation placement,
    Parameter parameter,
    String wire,
  ) {
    if (placement != .querystring) return true;
    _context.report(
      .querystringNotGenerated,
      'Parameter "$wire" is in: querystring (OpenAPI 3.2), which the client '
      'cannot send; the parameter is not generated.',
      parameter.location,
      fix: 'Describe the query string as query parameters at the source.',
    );
    return false;
  }

  /// The style of [parameter] as the IR keeps it: what the spec writes when
  /// its placement allows it, else null (the default style of the
  /// placement), with TOA564.
  ParameterStyle? _checkedStyle(
    Parameter parameter,
    ParameterLocation placement,
    String wire,
  ) {
    final style = parameter.style;
    final allowed = allowedStyles[placement];
    if (style == null || allowed == null || allowed.contains(style)) {
      return style;
    }
    final fallback = allowed.first;
    _context.report(
      .parameterStyleInvalid,
      'The style "${style.name}" is not allowed for a ${placement.name} '
      'parameter, which takes '
      '${[for (final s in allowed) '"${s.name}"'].join(', ')}; the default '
      'style "${fallback.name}" is used for "$wire".',
      parameter.location,
      fix: 'Use one of these styles at the source.',
    );
    return null;
  }

  ParameterIr _parameter(
    SpecOperation entry,
    Parameter parameter,
    ParameterLocation placement,
    String wire,
    NameScope scope,
    String prefix,
  ) {
    final override = _context.overrides.parameterAt(parameter.location);
    final written = override?.name;
    final given = written == null
        ? null
        : _context.checkedOverrideName(
            override!,
            'name',
            written,
            .member,
            what: 'argument',
          );
    final automatic = given == null ? _names.camel(wire) : null;
    final candidate = given ?? automatic ?? 'param';
    final (name, change) = scope.claim(
      candidate,
      alternatives: ['$candidate${_names.pascal(placement.name)}'],
    );
    final address = [
      'operations',
      entry.overrideKey,
      'parameters',
      '${placement.name}:$wire',
    ];
    if (given == null && automatic == null) {
      _context.report(
        .nameUnrepresentable,
        'Parameter "$wire" has no ASCII letter or digit; the argument is '
        'named "$name".',
        parameter.location,
        fix: 'Name the argument explicitly.',
        override: _context.overrideAt(address, {'name': 'argument'}),
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Parameter "$wire" would be the Dart name "$candidate"; the '
                  'argument is named "$name".'
            : 'Another argument of ${entry.overrideKey} is named '
                  '"$candidate"; the argument of ${placement.name} parameter '
                  '"$wire" is named "$name".',
        parameter.location,
        fix: 'Name the argument explicitly to keep the name stable.',
        override: _context.overrideAt(address, {'name': name}),
      );
    }
    if (given == null && automatic != null) {
      _context.checkLossyName(
        wire,
        name,
        parameter.location,
        what: 'Parameter',
        override: _context.overrideAt(address, {'name': name}),
      );
    }
    final (schema, contentType) = switch (parameter.schema) {
      final schema? => (schema, null),
      null => _content(parameter.content, parameter.location),
    };
    final mapped = schema == null
        ? const CoreType(.json)
        : _mapper.typeOf(
            schema,
            NameHint(prefix, _names.pascal(wire) ?? ''),
            direction: .request,
          );
    final custom = override?.dartType;
    final type = custom == null
        ? mapped
        : CustomType(
            type: custom.type,
            import: custom.import,
            converter: custom.converter,
            json: mapped.withNullable(false),
          );
    final required = placement == .path || parameter.required;
    return ParameterIr(
      name: name,
      wireName: wire,
      placement: placement,
      type: required ? type : type.withNullable(true),
      location: parameter.location,
      required: required,
      style: _checkedStyle(parameter, placement, wire),
      explode: parameter.explode,
      allowReserved: parameter.allowReserved,
      contentType: contentType,
      description: parameter.description,
      deprecated: parameter.deprecated,
      defaultValue: _defaults.of(schema),
    );
  }

  RequestBodyIr? _body(Operation operation, String method, String prefix) {
    final written = operation.requestBody;
    if (written == null) return null;
    final body = _context.model.resolve(written);
    if (body == null) return null;
    final (contentType, media) = _pick(
      body.content,
      body.location,
      'request body',
    );
    final kind = contentType == null ? BodyKind.none : _kind(contentType);
    final schema = media?.schema;
    final parts = kind == .multipart ? _parts.of(media, prefix) : null;
    // Parts are a class of their own.
    final type = parts == null ? _bodyType(schema, kind, prefix, method) : null;
    return RequestBodyIr(
      kind: kind,
      location: body.location,
      contentType: contentType,
      type: type,
      required: body.required,
      description: body.description,
      encoding: _encoding.of(media, kind),
      parts: parts,
    );
  }

  /// The type of a request body of [kind]: raw bytes have no model, as in
  /// responses, and text is a string.
  DartType? _bodyType(
    Schema? schema,
    BodyKind kind,
    String prefix,
    String method,
  ) {
    return switch ((schema, kind)) {
      (_, .bytes) => const CoreType(.binary),
      (_, .text || .eventStream) => const CoreType(.string),
      (null, _) => null,
      (final schema?, _) => _mapper.typeOf(
        schema,
        NameHint(prefix, 'Request'),
        direction: .request,
        patchBody: method.toLowerCase() == 'patch',
      ),
    };
  }

  List<ResponseIr> _responses(Operation operation, String prefix) {
    final responses = [
      for (final MapEntry(key: status, value: written)
          in operation.responses.entries)
        if (_context.model.resolve(written) case final response?)
          (
            status,
            response,
            _pick(response.content, response.location, 'response'),
          ),
    ];
    // Inline names carry the status only when several responses of the
    // same kind (success or error) have a body.
    final withBody = <String, int>{};
    for (final (status, _, (_, media)) in responses) {
      if (media?.schema == null && media?.itemSchema == null) continue;
      final base = _nameBase(status);
      withBody[base] = (withBody[base] ?? 0) + 1;
    }
    final result = <ResponseIr>[];
    for (final (status, response, (contentType, media)) in responses) {
      final kind = _responseKind(contentType, response);
      final success = status.startsWith('2');
      final base = _nameBase(status);
      final suffix = (withBody[base] ?? 0) > 1
          ? '$base${status == 'default' ? 'Default' : status.toUpperCase()}'
          : base;
      final schema = kind == .eventStream
          ? media?.itemSchema ?? media?.schema
          : media?.schema;
      final envelope = success && kind == .json && schema != null
          ? _envelope(schema)
          : null;
      final DartType? type = switch ((schema, kind)) {
        (_, .text) => const CoreType(.string),
        (_, .bytes) => const CoreType(.binary),
        (final schema?, _) => _mapper.typeOf(
          envelope ?? schema,
          NameHint(prefix, suffix),
          direction: .response,
        ),
        _ => null,
      };
      result.add(
        ResponseIr(
          status: status,
          kind: kind,
          location: response.location,
          contentType: contentType,
          type: type,
          envelopeKey: envelope == null ? null : 'data',
          description: response.description,
          sensitive: _secrets.isSecret(envelope ?? schema, type),
        ),
      );
    }
    return result;
  }

  /// How the body of [response] in [contentType] is read: a form or a
  /// multipart response is bytes (TOA650), since a client does not read
  /// forms.
  BodyKind _responseKind(String? contentType, Response response) {
    if (contentType == null) return .none;
    final kind = _kind(contentType);
    if (kind != .form && kind != .multipart) return kind;
    _context.report(
      .mediaTypeAsBytes,
      'The response is "$contentType", which the client reads as bytes; its '
      'schema is not used.',
      response.location.child('content').child(contentType),
      fix: 'Use a JSON media type at the source if the schema matters.',
    );
    return .bytes;
  }

  /// How inline types of a response with [status] are named: `Response`
  /// for 2xx, `Error` for 4xx, 5xx and `default`, `Response` with the status
  /// for the rest.
  static String _nameBase(String status) {
    if (status.startsWith('2')) return 'Response';
    if (status.startsWith('4') || status.startsWith('5')) return 'Error';
    if (status == 'default') return 'Error';
    return 'Response${status.toUpperCase()}';
  }

  /// The schema of `data` when [schema] is an envelope `{data: T}`: an
  /// object whose only property is the required `data` (R6.4).
  Schema? _envelope(Schema schema) {
    final resolved = _context.model.resolveSchema(schema);
    if (resolved is! SchemaObject) return null;
    final data = resolved.properties['data'];
    if (data == null ||
        resolved.properties.length != 1 ||
        !resolved.required.contains('data') ||
        resolved.allOf.isNotEmpty ||
        resolved.additionalProperties is SchemaObject) {
      return null;
    }
    return data;
  }

  /// The documented errors (R11.4): `Never` without any, the one body
  /// type when all errors share it, else the body type of each status. A
  /// status without a body uses `errors.default_schema` when it is set.
  ErrorsIr _errors(List<ResponseIr> responses) {
    final fallback = _defaultErrorType();
    final cases = [
      for (final response in responses)
        if (response.isError) (response.status, response.type ?? fallback),
    ];
    if (cases.isEmpty) {
      return fallback == null
          ? const NoErrors()
          : SingleError(fallback, const []);
    }
    final types = {for (final (_, type) in cases) type};
    if (types.length == 1 && types.single != null) {
      return SingleError(types.single!, [for (final (s, _) in cases) s]);
    }
    return ErrorsByStatus(
      cases,
      sensitive: {
        for (final response in responses)
          if (response.isError &&
              (response.type == null
                  ? _secrets.isDefaultErrorSecret(fallback)
                  : response.sensitive))
            response.status,
      },
    );
  }

  DartType? _defaultErrorType() {
    final key = _context.defaultErrorSchema;
    if (key == null) return null;
    final schema = _context.model.document.components?.schemas[key];
    if (schema == null) return null;
    return _mapper.typeOfComponent(schema, direction: .response);
  }

  /// The media type the client uses: JSON first, then forms, text, event
  /// streams and anything else, each in document order. [location] is the
  /// object that has [content] and [what] says what it is. The media types
  /// that are dropped are reported (TOA651), and so is a chosen one that
  /// becomes bytes and takes its schema with it (TOA650).
  (String?, MediaType?) _pick(
    Map<String, RefOr<MediaType>> content,
    SpecLocation location,
    String what,
  ) {
    if (content.isEmpty) return (null, null);
    const preference = [
      BodyKind.json,
      BodyKind.multipart,
      BodyKind.form,
      BodyKind.text,
      BodyKind.eventStream,
      BodyKind.bytes,
    ];
    for (final kind in preference) {
      for (final MapEntry(key: type, value: written) in content.entries) {
        if (_kind(type) != kind) continue;
        final media = _context.model.resolve(written);
        // A variant of the chosen type (`application/json; profile=...`) or
        // another JSON type (also `text/json`) has the same use: nothing is
        // lost.
        final dropped = [
          for (final other in content.keys)
            if (other != type &&
                _baseType(other) != _baseType(type) &&
                !(kind == .json && _isJson(other)))
              other,
        ];
        if (dropped.isNotEmpty) {
          _context.report(
            .mediaTypesDropped,
            'The $what offers ${content.length} media types; "$type" is '
            'used and ${_quoted(dropped)} '
            '${dropped.length == 1 ? 'is' : 'are'} dropped.',
            location.child('content'),
            fix:
                'Offer one media type at the source if the client should '
                'use another.',
          );
        }
        final schema = media?.schema;
        if (kind == .bytes && schema != null && !_isPlain(schema)) {
          _context.report(
            .mediaTypeAsBytes,
            'The media type "$type" of the $what is not JSON, a form, text '
            'or an event stream, so it is sent as bytes and its schema is '
            'not used.',
            location.child('content').child(type),
            fix:
                'Use a JSON media type at the source if the schema '
                'matters.',
          );
        }
        return (type, media);
      }
    }
    return (null, null);
  }

  static String _quoted(List<String> types) =>
      [for (final type in types) '"$type"'].join(', ');

  /// Whether [schema] says no more than "bytes": nothing, a boolean or a
  /// string of any format.
  bool _isPlain(Schema schema) {
    final resolved = _context.model.resolveSchema(schema);
    if (resolved is! SchemaObject) return true;
    return resolved.types.every((t) => t == .string || t == .nullType) &&
        resolved.properties.isEmpty &&
        resolved.allOf.isEmpty &&
        resolved.oneOf.isEmpty &&
        resolved.anyOf.isEmpty &&
        resolved.items == null;
  }

  (Schema?, String?) _content(
    Map<String, RefOr<MediaType>> content,
    SpecLocation location,
  ) {
    final (type, media) = _pick(content, location, 'parameter');
    return (media?.schema, type);
  }

  /// [contentType] without its parameters, in lower case.
  static String _baseType(String contentType) =>
      contentType.split(';').first.trim().toLowerCase();

  /// Whether [contentType] is JSON, also as `text/json`, which is a text
  /// type for [_kind] but is read as JSON by every server that sends it.
  static bool _isJson(String contentType) =>
      _kind(contentType) == .json || _baseType(contentType) == 'text/json';

  static BodyKind _kind(String contentType) {
    final type = _baseType(contentType);
    if (type == 'application/json' || type.endsWith('+json')) return .json;
    if (type == 'multipart/form-data') return .multipart;
    if (type == 'application/x-www-form-urlencoded') return .form;
    if (type == 'text/event-stream') return .eventStream;
    if (type.startsWith('text/')) return .text;
    return .bytes;
  }
}
