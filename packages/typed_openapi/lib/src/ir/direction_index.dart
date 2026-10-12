import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';
import 'ir.dart';
import 'response_statuses.dart';
import 'schema_shapes.dart';

/// Where each schema is used, requests or responses, to split models by
/// direction (spec decision 4).
///
/// A schema is split into a response model and a request model when it, or
/// a schema inside it, has a `readOnly` or `writeOnly` property and it is
/// used in both directions. The request body of a PATCH operation is not a
/// use of its schema here: it is recorded apart, and a PATCH body schema
/// that is used anywhere else gets a PATCH model of its own. A schema used
/// only as a PATCH body is a request model.
final class DirectionIndex {
  /// Creates an index of [_model] with no uses; a property for which
  /// [isExcluded] is true is not part of any model, so it counts for
  /// nothing.
  DirectionIndex(
    this._model, {
    bool Function(SpecLocation)? isExcluded,
  }) : _isExcluded = isExcluded ?? ((_) => false);

  final SpecModel _model;
  final bool Function(SpecLocation) _isExcluded;
  final Map<SpecLocation, Set<ModelDirection>> _uses = {};
  final Set<(SpecLocation, ModelDirection)> _seen = {};
  final Map<SpecLocation, bool> _directional = {};
  final Set<SpecLocation> _patchBodies = {};

  late final RefFollower _refs = RefFollower(
    _model.resolveSchema,
    siblings: _model.document.version != .v30,
  );

  /// Records the schemas of [operation]'s parameters and request body as
  /// used in requests and those of its responses as used in responses; the
  /// body of a [method] `patch` is a PATCH body.
  void addOperation(Operation operation, PathItem item, String method) {
    for (final written in [...item.parameters, ...operation.parameters]) {
      final parameter = _model.resolve(written);
      if (parameter == null) continue;
      add(parameter.schema, .request);
      _content(parameter.content, .request);
    }
    if (operation.requestBody case final written?) {
      final content = _model.resolve(written)?.content ?? const {};
      if (method.toLowerCase() == 'patch') {
        for (final media in content.values) {
          _patchBody(_model.resolve(media)?.schema);
        }
      } else {
        _content(content, .request);
      }
    }
    for (final MapEntry(:key, :value) in operation.responses.entries) {
      if (!ResponseStatuses.isGenerated(key)) continue;
      _content(_model.resolve(value)?.content ?? const {}, .response);
    }
  }

  void _content(
    Map<String, RefOr<MediaType>> content,
    ModelDirection direction,
  ) {
    for (final written in content.values) {
      final media = _model.resolve(written);
      add(media?.schema, direction);
      add(media?.itemSchema, direction);
    }
  }

  /// Records [schema] as a PATCH body; the schemas inside it are used in
  /// requests.
  void _patchBody(Schema? schema) {
    final target = schema == null ? null : bodyTarget(schema);
    if (target == null) return;
    _patchBodies.add(target.location);
    for (final child in _children(target)) {
      add(child, .request);
    }
  }

  /// The schema a request body [schema] stands for: the schema a `$ref`
  /// reaches, and through wrappers the schema of `allOf` with one part or
  /// of a union with one branch besides `null`; null when it is not an
  /// object schema.
  SchemaObject? bodyTarget(Schema schema) {
    final seen = <SpecLocation>{};
    var current = _model.resolveSchema(schema);
    while (current is SchemaObject && seen.add(current.location)) {
      final single = SchemaShapes.singleOf(current, refs: _refs);
      if (single == null) return current;
      current = _model.resolveSchema(single);
    }
    return null;
  }

  /// Records [schema] and every schema inside it as used in [direction].
  void add(Schema? schema, ModelDirection direction) {
    if (schema is! SchemaObject) return;
    if (schema.ref != null) {
      add(_model.resolveSchema(schema), direction);
      return;
    }
    if (!_seen.add((schema.location, direction))) return;
    (_uses[schema.location] ??= {}).add(direction);
    for (final child in _children(schema)) {
      add(child, direction);
    }
  }

  /// Whether [schema] is a PATCH body that is also used elsewhere, so the
  /// PATCH body gets a model of its own.
  bool separatesPatch(SchemaObject schema) =>
      _patchBodies.contains(schema.location) &&
      _uses.containsKey(schema.location);

  /// Whether the schema at [location] is a PATCH body and nothing else
  /// uses it, so its model is the PATCH model.
  bool isPatchOnly(SpecLocation location) =>
      _patchBodies.contains(location) && !_uses.containsKey(location);

  /// Whether [schema] gets a response model and a request model.
  bool splits(SchemaObject schema) =>
      (_uses[schema.location]?.length ?? 0) > 1 && _isDirectional(schema);

  /// The one direction [schema] is used in, if it is used in one only.
  ModelDirection? onlyDirection(SchemaObject schema) =>
      switch (_uses[schema.location]) {
        final uses? when uses.length == 1 => uses.single,
        null when isPatchOnly(schema.location) => .request,
        _ => null,
      };

  /// Whether [schema] or a schema reachable from it has a `readOnly` or
  /// `writeOnly` property.
  ///
  /// The answer depends on the set of schemas reachable from [schema] only,
  /// not on the order schemas are asked in, also when they refer to each
  /// other. A search that finds none proves that for every schema it
  /// visited, since what they reach is inside the visited set; one that
  /// finds one proves it for its start only.
  bool _isDirectional(SchemaObject schema) {
    final known = _directional[schema.location];
    if (known != null) return known;
    final visited = <SpecLocation>{};
    final pending = [schema];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!visited.add(next.location)) continue;
      final cached = _directional[next.location];
      if (cached == false) continue;
      if (cached == true || _hasDirectionalProperty(next)) {
        return _directional[schema.location] = true;
      }
      for (final child in _children(next).reversed) {
        final resolved = _model.resolveSchema(child);
        if (resolved is SchemaObject) pending.add(resolved);
      }
    }
    for (final location in visited) {
      _directional[location] = false;
    }
    return false;
  }

  /// Whether a property of [schema] is `readOnly` or `writeOnly`, as
  /// written, through its `$ref`, in an annotation-only part of its
  /// `allOf` or in the one branch of a nullable `anyOf`/`oneOf`
  /// ([SchemaShapes.annotationSources]).
  bool _hasDirectionalProperty(SchemaObject schema) {
    for (final property in _properties(schema)) {
      if (SchemaShapes.annotationSources(
        property,
        refs: _refs,
      ).any((source) => source.readOnly || source.writeOnly)) {
        return true;
      }
    }
    return false;
  }

  Iterable<Schema> _properties(SchemaObject schema) => [
    for (final property in schema.properties.values)
      if (!_isExcluded(property.location)) property,
  ];

  List<Schema> _children(SchemaObject schema) => [
    ..._properties(schema),
    ?schema.items,
    ...schema.prefixItems,
    ?schema.additionalProperties,
    ...schema.allOf,
    ...schema.oneOf,
    ...schema.anyOf,
  ];
}
