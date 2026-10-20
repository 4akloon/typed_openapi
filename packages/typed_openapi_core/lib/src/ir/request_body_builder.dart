import '../model/operation.dart';
import '../model/schema.dart';
import 'body_encoding.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'parts_builder.dart';
import 'schema_mapper.dart';

/// Builds the request body of an operation (R10.4): picks its media type and
/// maps its type, its parts (multipart) and its encoding (forms).
final class RequestBodyBuilder {
  /// Creates a builder that maps types with [_mapper].
  RequestBodyBuilder(this._context, this._mapper)
    : _parts = PartsBuilder(_context, _mapper),
      _encoding = BodyEncoding(_context),
      _picker = MediaTypePicker(_context);

  final IrContext _context;
  final SchemaMapper _mapper;
  final PartsBuilder _parts;
  final BodyEncoding _encoding;
  final MediaTypePicker _picker;

  /// The request body of [operation], sent with [method]; [prefix] starts
  /// the names of its inline types.
  RequestBodyIr? of(Operation operation, String method, String prefix) {
    final written = operation.requestBody;
    if (written == null) return null;
    final body = _context.model.resolve(written);
    if (body == null) return null;
    final (contentType, media) = _picker.pick(
      body.content,
      body.location,
      'request body',
    );
    final kind = contentType == null
        ? BodyKind.none
        : MediaTypePicker.kindOf(contentType);
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
}
