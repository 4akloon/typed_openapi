import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'schema_mapper.dart';

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
  OperationBuilder(this._context, this._mapper);

  static const _names = DartNames();
  static final _variable = RegExp(r'\{([^}]*)\}');

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The IR of [entry], named [name]; null when its path template cannot
  /// be filled.
  OperationIr? build(SpecOperation entry, String name) {
    final operation = entry.operation;
    final prefix = _names.pascal(name) ?? name;
    final parameters = _parameters(entry, prefix);
    if (parameters == null) return null;
    final responses = _responses(operation, prefix);
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
      body: _body(operation, prefix),
      responses: responses,
      errors: _errors(responses),
    );
  }

  List<ParameterIr>? _parameters(SpecOperation entry, String prefix) {
    // Operation parameters replace path item parameters with the same name
    // and location.
    final byKey = <(ParameterLocation?, String?), Parameter>{};
    for (final written in [
      ...entry.item.parameters,
      ...entry.operation.parameters,
    ]) {
      final parameter = _context.model.resolve(written);
      if (parameter == null) continue;
      byKey[(parameter.placement, parameter.name)] = parameter;
    }
    final variables = [
      for (final match in _variable.allMatches(entry.path)) match[1]!,
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
    final sorted = byKey.values.toList()
      ..sort(
        (a, b) => order.indexOf(a.placement!) - order.indexOf(b.placement!),
      );
    return [
      for (final parameter in sorted)
        if (parameter.name case final wire?)
          _parameter(entry, parameter, wire, scope, prefix),
    ];
  }

  ParameterIr _parameter(
    SpecOperation entry,
    Parameter parameter,
    String wire,
    NameScope scope,
    String prefix,
  ) {
    final placement = parameter.placement!;
    final override = _context.overrides.parameterAt(parameter.location);
    final candidate = override?.name ?? _names.camel(wire) ?? 'param';
    final (name, change) = scope.claim(
      candidate,
      alternatives: ['$candidate${_names.pascal(placement.name)}'],
    );
    if (change != null) {
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
        override: _context.overrideAt(
          [
            'operations',
            entry.overrideKey,
            'parameters',
            '${placement.name}:$wire',
          ],
          {'name': name},
        ),
      );
    }
    final (schema, contentType) = switch (parameter.schema) {
      final schema? => (schema, null),
      null => _content(parameter.content),
    };
    final mapped = schema == null
        ? const CoreType(.json)
        : _mapper.typeOf(schema, NameHint(prefix, _names.pascal(wire) ?? ''));
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
      style: parameter.style,
      explode: parameter.explode,
      allowReserved: parameter.allowReserved,
      contentType: contentType,
      description: parameter.description,
      deprecated: parameter.deprecated,
    );
  }

  RequestBodyIr? _body(Operation operation, String prefix) {
    final written = operation.requestBody;
    if (written == null) return null;
    final body = _context.model.resolve(written);
    if (body == null) return null;
    final (contentType, media) = _pick(body.content);
    final kind = contentType == null ? BodyKind.none : _kind(contentType);
    final schema = media?.schema;
    return RequestBodyIr(
      kind: kind,
      location: body.location,
      contentType: contentType,
      type: schema == null
          ? null
          : _mapper.typeOf(schema, NameHint(prefix, 'Request')),
      required: body.required,
      description: body.description,
    );
  }

  List<ResponseIr> _responses(Operation operation, String prefix) {
    final responses = [
      for (final MapEntry(key: status, value: written)
          in operation.responses.entries)
        if (_context.model.resolve(written) case final response?)
          (status, response, _pick(response.content)),
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
      final kind = contentType == null ? BodyKind.none : _kind(contentType);
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
        ),
      );
    }
    return result;
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
    return ErrorsByStatus(cases);
  }

  DartType? _defaultErrorType() {
    final key = _context.config.defaultErrorSchema;
    if (key == null) return null;
    final schema = _context.model.document.components?.schemas[key];
    if (schema == null) return null;
    return _mapper.typeOfComponent(schema);
  }

  /// The media type the client uses: JSON first, then forms, text, event
  /// streams and anything else, each in document order.
  (String?, MediaType?) _pick(Map<String, RefOr<MediaType>> content) {
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
        return (type, _context.model.resolve(written));
      }
    }
    return (null, null);
  }

  (Schema?, String?) _content(Map<String, RefOr<MediaType>> content) {
    final (type, media) = _pick(content);
    return (media?.schema, type);
  }

  static BodyKind _kind(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    if (type == 'application/json' || type.endsWith('+json')) return .json;
    if (type == 'multipart/form-data') return .multipart;
    if (type == 'application/x-www-form-urlencoded') return .form;
    if (type == 'text/event-stream') return .eventStream;
    if (type.startsWith('text/')) return .text;
    return .bytes;
  }
}
