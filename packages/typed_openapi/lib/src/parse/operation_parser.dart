import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'schema_parser.dart';
import 'server_parser.dart';

/// Reads path items, operations and everything they contain: parameters,
/// request bodies, responses, headers, media types, encodings, examples,
/// servers and security requirements.
final class OperationParser {
  /// Creates a parser that reads from [_context] and reads schemas with
  /// [_schemas].
  OperationParser(this._context, this._schemas)
    : _servers = ServerParser(_context);

  final ParseContext _context;
  final SchemaParser _schemas;
  final ServerParser _servers;

  /// Reads the path item [raw] at [pointer].
  RefOr<PathItem>? pathItem(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .pathItem, _pathItem);

  /// Reads the parameter [raw] at [pointer].
  RefOr<Parameter>? parameter(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .parameter, _parameter);

  /// Reads the request body [raw] at [pointer].
  RefOr<RequestBody>? requestBody(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .requestBody, _requestBody);

  /// Reads the response [raw] at [pointer].
  RefOr<Response>? response(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .response, _response);

  /// Reads the header [raw] at [pointer].
  RefOr<Header>? header(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .header, _header);

  /// Reads the media type [raw] at [pointer].
  RefOr<MediaType>? mediaType(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .mediaType, _mediaType);

  /// Reads the example [raw] at [pointer].
  RefOr<Example>? example(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .example, _example);

  /// Reads the server [raw] at [pointer].
  Server? server(Object? raw, JsonPointer pointer) =>
      _servers.server(raw, pointer);

  /// Reads the security requirement [raw] at [pointer]; an entry that is not
  /// an object is reported and kept as a malformed requirement.
  SecurityRequirement securityRequirement(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'A security requirement', _requirement) ??
      _context.register(
        SecurityRequirement(
          location: _context.locate(pointer),
          schemes: {if (raw is String) raw: const []},
          isMalformed: true,
        ),
      );

  SecurityRequirement _requirement(ObjectReader r) => _context.register(
    SecurityRequirement(
      location: r.location,
      schemes: Map.unmodifiable({
        for (final name in r.keys.toList()) name: r.strings(name) ?? const [],
      }),
    ),
  );

  PathItem _pathItem(ObjectReader r) {
    final operations = <String, Operation>{};
    for (final method in PathItem.methods) {
      final operation = r.object(method, _operation);
      if (operation == null) continue;
      operations[method] = operation;
      if (method == 'query') {
        _context.note(.queryOperation, r.pointer.child(method));
      }
    }
    if (r.has('additionalOperations')) {
      _context.note(
        .additionalOperations,
        r.pointer.child('additionalOperations'),
      );
    }
    return _context.register(
      PathItem(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        operations: Map.unmodifiable(operations),
        additionalOperations:
            r.map('additionalOperations', _operationAt) ?? const {},
        servers: r.list('servers', server) ?? const [],
        parameters: r.list('parameters', parameter) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Operation? _operationAt(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'An operation', _operation);

  Operation _operation(ObjectReader r) {
    r.accept(const ['externalDocs', 'callbacks']);
    return _context.register(
      Operation(
        location: r.location,
        tags: r.strings('tags') ?? const [],
        summary: r.string('summary'),
        description: r.string('description'),
        operationId: r.string('operationId'),
        parameters: r.list('parameters', parameter) ?? const [],
        requestBody: switch (r.value('requestBody')) {
          (final raw,) => requestBody(raw, r.pointer.child('requestBody')),
          null => null,
        },
        responses:
            r.map('responses', response, skipExtensions: true) ?? const {},
        deprecated: r.boolean('deprecated') ?? false,
        security: r.list('security', securityRequirement),
        servers: r.list('servers', server) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Parameter _parameter(ObjectReader r) {
    final placement = r.requiredChoice(
      'in',
      ParameterLocation.values.asNameMap(),
    );
    if (placement == .querystring) {
      _context.note(.querystringParameter, r.pointer.child('in'));
    }
    return _context.register(
      Parameter(
        location: r.location,
        name: r.requiredString('name'),
        placement: placement,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        allowEmptyValue: r.boolean('allowEmptyValue') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RequestBody _requestBody(ObjectReader r) {
    if (!r.has('content')) {
      _context.report(
        .missingRequiredField,
        'The required field "content" is missing.',
        r.pointer,
        args: const ['content'],
      );
    }
    return _context.register(
      RequestBody(
        location: r.location,
        description: r.string('description'),
        content: r.map('content', mediaType) ?? const {},
        required: r.boolean('required') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Response _response(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.responseSummary, r.pointer.child('summary'));
    }
    r.accept(const ['links']);
    return _context.register(
      Response(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        headers: r.map('headers', header) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Header _header(ObjectReader r) {
    r.accept(const ['allowEmptyValue', 'allowReserved']);
    return _context.register(
      Header(
        location: r.location,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  MediaType _mediaType(ObjectReader r) {
    if (r.has('itemSchema')) {
      _context.note(.itemSchema, r.pointer.child('itemSchema'));
    }
    for (final key in const ['prefixEncoding', 'itemEncoding']) {
      if (r.has(key)) _context.note(.sequentialEncoding, r.pointer.child(key));
    }
    return _context.register(
      MediaType(
        location: r.location,
        schema: _schema(r, 'schema'),
        itemSchema: _schema(r, 'itemSchema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        encoding: r.map('encoding', _encodingAt) ?? const {},
        prefixEncoding: r.list('prefixEncoding', _encodingAt) ?? const [],
        itemEncoding: r.object('itemEncoding', _encoding),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Encoding? _encodingAt(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'An encoding', _encoding);

  Encoding _encoding(ObjectReader r) {
    r.accept(const ['encoding', 'prefixEncoding', 'itemEncoding']);
    return _context.register(
      Encoding(
        location: r.location,
        contentType: r.string('contentType'),
        headers: r.map('headers', header) ?? const {},
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Example _example(ObjectReader r) {
    for (final key in const ['dataValue', 'serializedValue']) {
      if (r.has(key)) _context.note(.exampleValues, r.pointer.child(key));
    }
    return _context.register(
      Example(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        value: r.value('value'),
        dataValue: r.value('dataValue'),
        serializedValue: r.string('serializedValue'),
        externalValue: r.string('externalValue'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ParameterStyle? _style(ObjectReader r) {
    final style = r.choice('style', ParameterStyle.values.asNameMap());
    if (style == .cookie) _context.note(.cookieStyle, r.pointer.child('style'));
    return style;
  }

  Schema? _schema(ObjectReader r, String key) => switch (r.value(key)) {
    (final raw,) => _schemas.parse(raw, r.pointer.child(key)),
    null => null,
  };
}
