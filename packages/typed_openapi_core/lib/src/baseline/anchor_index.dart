import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';

/// The logical addresses of a spec's nodes: the part of a baseline anchor
/// that survives edits elsewhere in the spec.
///
/// An address is the path of keys the overrides file uses for the node:
/// `operations`, `METHOD /path`, then `parameters` and `in:name` for a
/// parameter the operation defines itself; `schemas` and the
/// `components.schemas` key (a key that defines its schema wins over one
/// that refers to it), then `properties` and the name for a property. A
/// path-level parameter, a webhook and a node no address reaches have
/// none; their anchor is the file and the JSON pointer.
final class AnchorIndex {
  /// Indexes the operations, parameters, schemas and properties of [model],
  /// whose files are [documents].
  AnchorIndex(SpecModel model, SpecDocuments documents) {
    for (final document in documents.loaded) {
      _documents[documents.displayPath(document.uri)] = document.uri;
    }
    for (final MapEntry(key: path, value: written)
        in model.document.paths.entries) {
      final item = model.resolve(written);
      if (item == null) continue;
      for (final MapEntry(key: method, value: operation)
          in item.operations.entries) {
        final address = ['operations', '${method.toUpperCase()} $path'];
        _put(operation.location, address);
        for (final parameter in operation.parameters) {
          if (parameter case Inline(
            value: Parameter(:final name?, :final placement?, :final location),
          )) {
            _put(location, [
              ...address,
              'parameters',
              '${placement.name}:$name',
            ]);
          }
        }
      }
    }
    final schemas = model.document.components?.schemas ?? const {};
    final keys = [
      for (final MapEntry(:key, :value) in schemas.entries)
        if (_isDefinition(value)) key,
      for (final MapEntry(:key, :value) in schemas.entries)
        if (!_isDefinition(value)) key,
    ];
    for (final key in keys) {
      final schema = model.resolveSchema(schemas[key]!);
      if (schema == null) continue;
      _put(schema.location, ['schemas', key]);
      if (schema is! SchemaObject) continue;
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        _put(property.location, ['schemas', key, 'properties', name]);
      }
    }
  }

  /// An index without logical addresses, for a spec that was not read.
  AnchorIndex.none();

  final Map<String, Uri> _documents = {};
  final Map<SpecLocation, List<String>> _addresses = {};

  /// The address of the closest node at or above [pointer] in the file
  /// diagnostics name [file], and the pointer from that node down to
  /// [pointer]; null when no node on the way has an address.
  (List<String>, JsonPointer)? addressOf(String file, JsonPointer pointer) {
    final uri = _documents[file];
    if (uri == null) return null;
    final tokens = pointer.tokens;
    for (var length = tokens.length; length >= 0; length--) {
      final at = tokens.take(length).fold(JsonPointer.root, _child);
      final address = _addresses[SpecLocation(uri, at)];
      if (address == null) continue;
      return (address, tokens.skip(length).fold(JsonPointer.root, _child));
    }
    return null;
  }

  void _put(SpecLocation location, List<String> address) =>
      _addresses.putIfAbsent(location, () => address);

  static JsonPointer _child(JsonPointer pointer, String token) =>
      pointer.child(token);

  static bool _isDefinition(Schema schema) =>
      schema is! SchemaObject || schema.ref == null;
}
