import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';
import 'ir.dart';

/// Where each schema is used, requests or responses, to split models by
/// direction (spec decision 4).
///
/// A schema is split into a response model and a request model when it, or
/// a schema inside it, has a `readOnly` or `writeOnly` property and it is
/// used in both directions. The request body of a PATCH operation is not a
/// use of its schema here: it is recorded apart, and a PATCH body schema
/// that is used anywhere else gets a PATCH model of its own.
final class DirectionIndex {
  /// Creates an index of [_model] with no uses.
  DirectionIndex(this._model);

  final SpecModel _model;
  final Map<SpecLocation, Set<ModelDirection>> _uses = {};
  final Set<(SpecLocation, ModelDirection)> _seen = {};
  final Map<SpecLocation, bool> _directional = {};
  final Set<SpecLocation> _patchBodies = {};

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
    for (final written in operation.responses.values) {
      _content(_model.resolve(written)?.content ?? const {}, .response);
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
    if (schema == null) return;
    final resolved = _model.resolveSchema(schema);
    if (resolved is! SchemaObject) return;
    _patchBodies.add(resolved.location);
    for (final child in _children(resolved)) {
      add(child, .request);
    }
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

  /// Whether [schema] gets a response model and a request model.
  bool splits(SchemaObject schema) =>
      (_uses[schema.location]?.length ?? 0) > 1 && _isDirectional(schema);

  /// The one direction [schema] is used in, if it is used in one only.
  ModelDirection? onlyDirection(SchemaObject schema) =>
      switch (_uses[schema.location]) {
        final uses? when uses.length == 1 => uses.single,
        _ => null,
      };

  /// Whether [schema] or a schema inside it has a `readOnly` or `writeOnly`
  /// property.
  bool _isDirectional(SchemaObject schema) {
    final known = _directional[schema.location];
    if (known != null) return known;
    // A cycle is not directional by itself.
    _directional[schema.location] = false;
    var result = false;
    for (final property in schema.properties.values) {
      final resolved = _model.resolveSchema(property);
      if (resolved is SchemaObject &&
          (resolved.readOnly || resolved.writeOnly)) {
        result = true;
      }
      if (property is SchemaObject &&
          (property.readOnly || property.writeOnly)) {
        result = true;
      }
    }
    if (!result) {
      for (final child in _children(schema)) {
        final resolved = _model.resolveSchema(child);
        if (resolved is SchemaObject && _isDirectional(resolved)) {
          result = true;
          break;
        }
      }
    }
    return _directional[schema.location] = result;
  }

  static List<Schema> _children(SchemaObject schema) => [
    ...schema.properties.values,
    ?schema.items,
    ...schema.prefixItems,
    ?schema.additionalProperties,
    ...schema.allOf,
    ...schema.oneOf,
    ...schema.anyOf,
  ];
}
