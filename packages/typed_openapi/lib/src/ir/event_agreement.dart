import 'dart:convert';

import '../model/media_type.dart';
import '../model/schema.dart';
import 'ir_context.dart';

/// Decides from the spec, before any type is mapped, whether the event
/// streams of an operation's successes describe their events the same way:
/// by `itemSchema` or by `schema`, each the same schema. Mapping an inline
/// schema twice would declare it twice, so the answer cannot come from the
/// mapped types.
final class EventAgreement {
  /// Creates the check; it reads schemas through [_context].
  const EventAgreement(this._context);

  final IrContext _context;

  /// Whether every media type of [medias] (null for none) describes its
  /// events as the first does.
  bool agree(Iterable<MediaType?> medias) {
    final keys = [for (final media in medias) _keyOf(media)];
    return keys.every((key) => _same(keys.first, key));
  }

  /// The way [media] describes its events: where the description is
  /// (`itemSchema` or `schema`) and the schema at the end of its `$ref`s.
  (bool, Schema?)? _keyOf(MediaType? media) {
    if (media?.itemSchema case final item?) {
      return (true, _context.model.resolveSchema(item));
    }
    if (media?.schema case final schema?) {
      return (false, _context.model.resolveSchema(schema));
    }
    return null;
  }

  bool _same((bool, Schema?)? a, (bool, Schema?)? b) {
    if (a == null || b == null) return a == b;
    return a.$1 == b.$1 && _sameSchema(a.$2, b.$2);
  }

  /// Whether [a] and [b] are one schema, or two in one document that are
  /// written alike.
  bool _sameSchema(Schema? a, Schema? b) {
    if (a == null || b == null) return a == b;
    if (a.location == b.location) return true;
    if (a.location.document != b.location.document) return false;
    final documents = _context.documents;
    final x = documents[a.location.document]?.valueAt(a.location.pointer);
    final y = documents[b.location.document]?.valueAt(b.location.pointer);
    return x != null && y != null && jsonEncode(x.$1) == jsonEncode(y.$1);
  }
}
