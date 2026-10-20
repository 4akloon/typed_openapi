import 'dart:convert';

import '../model/schema.dart';
import '../model/spec_node.dart';
import 'ir_context.dart';
import 'mapping_state.dart';
import 'model_notices.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';

/// Merges the `allOf` parts of a schema into the flat properties of a model
/// (R6.3).
final class AllOfMerger {
  /// A merger for the client of [_context].
  const AllOfMerger(this._context, this._queries, this._notices);

  final IrContext _context;
  final SchemaQueries _queries;
  final ModelNotices _notices;

  /// The properties, required names and `additionalProperties` of [schema]
  /// with its `allOf` parts merged in, parts first and in order. A property,
  /// or `additionalProperties`, that a later part defines again with another
  /// schema is reported; the later one is used. A part an override excludes
  /// is merged all the same, because the model is flat and the exclude only
  /// removes the part's own declaration (TOA254 says so). A discriminator on
  /// a part does not matter here: the part's subtypes are picked where the
  /// part is used as a type.
  ModelParts merge(SchemaObject schema) {
    final run = _MergeRun(this)..add(schema);
    return ModelParts(run.properties, run.required, run.additional);
  }

  /// Merges the parts written in the `allOf` of [part] into [run].
  void _mergeParts(_MergeRun run, SchemaObject part) {
    for (final written in part.allOf) {
      // A part that only annotates adds no property: its `nullable` and
      // its description belong to the schema that has the `allOf`.
      if (SchemaShapes.isAnnotationOnly(written)) continue;
      final resolved = _queries.resolved(written);
      if (resolved == null) continue;
      if (_context.overrides.schemaAt(resolved.location)?.exclude ?? false) {
        _notices.excludedPartMerged(written);
      }
      if (_isNotObject(resolved)) {
        _notices.partIgnored(written);
        continue;
      }
      run.add(resolved);
      _notices.branchesBesideModel(resolved);
    }
  }

  /// Whether [part] has no properties of its own and is an enum, a union or
  /// a scalar, so it cannot be merged into a model.
  bool _isNotObject(SchemaObject part) =>
      part.properties.isEmpty &&
      part.allOf.isEmpty &&
      (SchemaShapes.enumValues(part) != null ||
          _queries.branches(part) != null ||
          part.types.any((t) => t != .object && t != .nullType));

  /// Takes the properties and `additionalProperties` of [part] into [run].
  void _mergeOwn(_MergeRun run, SchemaObject part) {
    for (final MapEntry(key: name, value: property)
        in part.properties.entries) {
      final earlier = run.properties[name];
      if (earlier != null && !_same(earlier, property)) {
        _notices.propertyConflict(name, property);
      }
      run.properties[name] = property;
    }
    if (part.additionalProperties case final later?) {
      final earlier = run.additional;
      if (earlier != null && !_same(earlier, later)) {
        _notices.additionalConflict(later);
      }
      run.additional = later;
    }
    run.required.addAll(part.required);
  }

  /// Whether two property schemas are the same: one schema through
  /// `$ref`s, or equal as written.
  bool _same(Schema a, Schema b) {
    final x = _context.model.resolveSchema(a)?.location;
    final y = _context.model.resolveSchema(b)?.location;
    if (x == y) return true;
    if (x == null || y == null) return false;
    final raw = _context.documents[x.document]?.valueAt(x.pointer);
    final other = _context.documents[y.document]?.valueAt(y.pointer);
    return raw != null &&
        other != null &&
        jsonEncode(raw.$1) == jsonEncode(other.$1);
  }
}

/// What one merge has collected so far.
final class _MergeRun {
  _MergeRun(this._merger);

  final AllOfMerger _merger;
  final Map<String, Schema> properties = {};
  final Set<String> required = {};
  final Set<SpecLocation> _seen = {};
  Schema? additional;

  /// Merges [part], once: its own parts first, then its own properties.
  void add(SchemaObject part) {
    if (!_seen.add(part.location)) return;
    _merger._mergeParts(this, part);
    _merger._mergeOwn(this, part);
  }
}
