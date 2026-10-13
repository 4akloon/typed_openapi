import '../model/operation.dart';
import '../model/schema.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'response_secrets.dart';
import 'response_statuses.dart';
import 'schema_mapper.dart';

/// Builds the responses and the errors of an operation (R10.6, R11.4):
/// picks a media type per response, maps the body types and unwraps
/// envelopes (R6.4).
final class ResponseBuilder {
  /// Creates a builder that maps types with [_mapper].
  ResponseBuilder(this._context, this._mapper)
    : _secrets = ResponseSecrets(_context),
      _statuses = ResponseStatuses(_context),
      _picker = MediaTypePicker(_context);

  final IrContext _context;
  final SchemaMapper _mapper;
  final ResponseSecrets _secrets;
  final ResponseStatuses _statuses;
  final MediaTypePicker _picker;

  /// The generated responses of [operation] with the media type used for
  /// each, before any type is mapped: for the method that returns the
  /// [events], the event stream of each success that has one. When the
  /// operation [hasStreamMethod], the event streams of its successes are not
  /// dropped (TOA651). The method that returns the body never uses a
  /// success's event stream as its body.
  List<PickedResponse> pick(
    Operation operation, {
    bool events = false,
    bool hasStreamMethod = false,
  }) => [
    for (final (status, written) in _statuses.of(operation))
      if (_context.model.resolve(written) case final response?)
        (
          status,
          response,
          (events && status.startsWith('2') ? _eventStream(response) : null) ??
              _picker.pick(
                response.content,
                response.location,
                'response',
                hasStreamMethod: hasStreamMethod && status.startsWith('2'),
                chooseEvents: events || !status.startsWith('2'),
              ),
        ),
  ];

  /// The `text/event-stream` media type of [response], if it has one.
  (String?, MediaType?)? _eventStream(Response response) {
    for (final MapEntry(:key, :value) in response.content.entries) {
      if (MediaTypePicker.kindOf(key) == .eventStream) {
        return (key, _context.model.resolve(value));
      }
    }
    return null;
  }

  /// The IR of the picked [responses]; [prefix] starts the names of their
  /// inline types.
  List<ResponseIr> of(List<PickedResponse> responses, String prefix) {
    final withBody = ResponseStatuses.bodyCounts(responses);
    final result = <ResponseIr>[];
    for (final (status, response, (contentType, media)) in responses) {
      final kind = _responseKind(contentType, response);
      final success = status.startsWith('2');
      final base = ResponseStatuses.nameOf(status, shared: false);
      final suffix = ResponseStatuses.nameOf(
        status,
        shared: (withBody[base] ?? 0) > 1,
      );
      final schema = kind == .eventStream
          ? media?.itemSchema ?? media?.schema
          : media?.schema;
      final envelope = success && kind == .json && schema != null
          ? _envelope(schema)
          : null;
      final type = _bodyType(
        envelope ?? schema,
        kind,
        NameHint(prefix, suffix),
      );
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

  /// The type of a response body of [kind] whose schema is [schema].
  DartType? _bodyType(Schema? schema, BodyKind kind, NameHint hint) =>
      switch ((schema, kind)) {
        (_, .text || .eventStream) => const CoreType(.string),
        (_, .bytes) => const CoreType(.binary),
        (final schema?, _) => _mapper.typeOf(
          schema,
          hint,
          direction: .response,
        ),
        _ => null,
      };

  /// How the body of [response] in [contentType] is read: a form or a
  /// multipart response is bytes (TOA650), since a client does not read
  /// forms.
  BodyKind _responseKind(String? contentType, Response response) {
    if (contentType == null) return .none;
    final kind = MediaTypePicker.kindOf(contentType);
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
  ErrorsIr errors(List<ResponseIr> responses) {
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
      sensitive: _secrets.errorStatuses(responses, fallback),
    );
  }

  DartType? _defaultErrorType() {
    final key = _context.defaultErrorSchema;
    if (key == null) return null;
    final schema = _context.model.document.components?.schemas[key];
    if (schema == null) return null;
    return _mapper.typeOfComponent(schema, direction: .response);
  }
}
