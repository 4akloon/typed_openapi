import 'dart:convert';

import '../model/schema.dart';
import 'default_matcher.dart';
import 'ir_context.dart';
import 'ref_follower.dart';
import 'schema_shapes.dart';

/// Reads the `default` of a schema the way a model field does (M6): the
/// first one wins among the schema's own keywords, the schema it stands for
/// (the one part of an `allOf`, the one branch of a nullable `anyOf` or
/// `oneOf`) and the schema a `$ref` names. The keywords written next to a
/// `$ref` count from OpenAPI 3.1; 3.0 ignores them. A default that does not
/// fit the `enum` or `format` of those schemas is reported (TOA660) and not
/// kept.
final class SchemaDefaults {
  /// Creates the reader for the spec of [_context].
  SchemaDefaults(this._context);

  static const _matcher = DefaultMatcher();

  final IrContext _context;

  // Lazy because a field initializer cannot read `_context`.
  late final RefFollower _refs = RefFollower.of(_context.model);

  /// The `default` of [schema], wrapped so that an explicit `null` default
  /// differs from none; null when [schema] is null, no source has one, or it
  /// does not fit.
  (Object?,)? of(Schema? schema) {
    if (schema == null) return null;
    final sources = SchemaShapes.annotationSources(schema, refs: _refs);
    for (final source in sources) {
      if (source.ref != null && !_refs.siblings) continue;
      if (source.defaultValue case final value?) {
        return _fits(source, value, sources) ? value : null;
      }
    }
    return null;
  }

  bool _fits(
    SchemaObject source,
    (Object?,) value,
    List<SchemaObject> sources,
  ) {
    final reason = _matcher.mismatch(value.$1, sources);
    if (reason == null) return true;
    _context.report(
      .defaultValueInvalid,
      'The default ${jsonEncode(value.$1)} $reason, so it is not '
      'documented as the default.',
      source.location.child('default'),
      fix: 'Use a default that fits the schema at the source.',
    );
    return false;
  }
}
