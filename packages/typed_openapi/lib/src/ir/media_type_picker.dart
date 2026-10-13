import '../model/media_type_name.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';

/// A generated response of an operation: its status, the Response Object and
/// the media type the client uses with that media type's object.
typedef PickedResponse = (String, Response, (String?, MediaType?));

/// Picks the media type of a request body, a response or a parameter's
/// `content`, and tells the kind of body a media type is.
final class MediaTypePicker {
  /// Creates the picker; it reports through [_context].
  const MediaTypePicker(this._context);

  final IrContext _context;

  /// The media type the client uses: JSON first, then forms, text, event
  /// streams and anything else, each in document order. [location] is the
  /// object that has [content] and [what] says what it is. The media types
  /// that are dropped are reported (TOA651), and so is a chosen one that
  /// becomes bytes and takes its schema with it (TOA650). An event stream
  /// is not dropped when [hasStreamMethod]: another method returns it.
  (String?, MediaType?) pick(
    Map<String, RefOr<MediaType>> content,
    SpecLocation location,
    String what, {
    bool hasStreamMethod = false,
  }) {
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
      for (final type in content.keys) {
        if (kindOf(type) != kind) continue;
        final media = _context.model.resolve(content[type]!);
        _reportDropped(
          content,
          type,
          location,
          what,
          hasStreamMethod: hasStreamMethod,
        );
        final schema = media?.schema;
        if (kind == .bytes && schema != null) {
          _reportBytes(schema, type, location, what);
        }
        return (type, media);
      }
    }
    return (null, null);
  }

  /// Reports the media types of [content] that [type] makes the client
  /// drop (TOA651). A variant of the chosen type (`application/json;
  /// profile=...`) or another JSON type has the same
  /// use: nothing is lost.
  void _reportDropped(
    Map<String, RefOr<MediaType>> content,
    String type,
    SpecLocation location,
    String what, {
    required bool hasStreamMethod,
  }) {
    final dropped = [
      for (final other in content.keys)
        if (other != type &&
            !(hasStreamMethod && kindOf(other) == .eventStream) &&
            MediaTypeName(other).base != MediaTypeName(type).base &&
            !(kindOf(type) == .json && kindOf(other) == .json))
          other,
    ];
    if (dropped.isEmpty) return;
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

  /// Reports a chosen media type that becomes bytes and takes its [schema]
  /// with it (TOA650).
  void _reportBytes(
    Schema schema,
    String type,
    SpecLocation location,
    String what,
  ) {
    if (_isPlain(schema)) return;
    _context.report(
      .mediaTypeAsBytes,
      'The media type "$type" of the $what is not JSON, a form, text '
      'or an event stream, so it is sent as bytes and its schema is '
      'not used.',
      location.child('content').child(type),
      fix: 'Use a JSON media type at the source if the schema matters.',
    );
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

  /// The schema and media type of a parameter's `content`.
  (Schema?, String?) content(
    Map<String, RefOr<MediaType>> content,
    SpecLocation location,
  ) {
    final (type, media) = pick(content, location, 'parameter');
    return (media?.schema, type);
  }

  /// How a body of [contentType] is read and written.
  static BodyKind kindOf(String contentType) {
    final name = MediaTypeName(contentType);
    if (name.isJson) return .json;
    final type = name.base;
    if (type == 'multipart/form-data') return .multipart;
    if (type == 'application/x-www-form-urlencoded') return .form;
    if (type == 'text/event-stream') return .eventStream;
    if (type.startsWith('text/')) return .text;
    return .bytes;
  }
}
