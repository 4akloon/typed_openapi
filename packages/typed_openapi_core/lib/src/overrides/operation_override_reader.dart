import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import 'generation_field_reader.dart';
import 'override_field_reader.dart';
import 'override_keys.dart';
import 'override_set.dart';
import 'sse_override_reader.dart';

/// Reads the entries of the `operations` section: an operation with its
/// parameters, request body and responses.
final class OperationOverrideReader {
  /// Creates a reader that works through [_fields] and [_generation].
  const OperationOverrideReader(this._fields, this._generation);

  final OverrideFieldReader _fields;
  final GenerationFieldReader _generation;

  static final _methodAndPath = RegExp(r'^([A-Za-z]+) (/.*)$');

  /// The operation override [entry] at [at] under [key]; null, after a
  /// report, for a method that is not an OpenAPI operation method.
  OperationOverride? operation(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _fields.checkKeys(entry, OverrideKeys.operation, at);
    final address = _address(key, at);
    if (address == null) return null;
    final body = _fields.map(entry, 'requestBody', at);
    return OperationOverride(
      key: key,
      pointer: at,
      reason: _fields.string(entry, 'reason', at),
      operationId: address.method == null ? key : null,
      method: address.method,
      path: address.path,
      name: _fields.string(entry, 'name', at),
      exclude: _fields.boolean(entry, 'exclude', at),
      group: _fields.string(entry, 'group', at),
      sse: SseOverrideReader(_fields).read(entry, at),
      parameters: [
        for (final (name, value, p) in _fields.entries(entry, 'parameters', at))
          ?_parameter(name, value, p),
      ],
      requestBody: body == null ? null : _body(body, at.child('requestBody')),
      responses: [
        for (final (status, value, p) in _fields.entries(
          entry,
          'responses',
          at,
        ))
          _response(status, value, p),
      ],
    );
  }

  /// The method and path an operation key names: both null for an
  /// `operationId`; null itself, after a report, for a method that is not an
  /// OpenAPI operation method.
  ({String? method, String? path})? _address(String key, JsonPointer at) {
    final match = _methodAndPath.firstMatch(key);
    if (match == null) return (method: null, path: null);
    final method = match[1]!.toLowerCase();
    if (PathItem.methods.contains(method)) {
      return (method: method, path: match[2]);
    }
    _fields.invalid(
      'The method "${match[1]}" is not an OpenAPI operation method.',
      at,
      fix:
          'Write the key as an operationId, or as METHOD /path with one '
          'of ${PathItem.methods.map((m) => m.toUpperCase()).join(', ')}.',
    );
    return null;
  }

  ParameterOverride? _parameter(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _fields.checkKeys(entry, OverrideKeys.parameter, at);
    var name = key;
    ParameterLocation? placement;
    final colon = key.indexOf(':');
    if (colon > 0) {
      placement = ParameterLocation.values.asNameMap()[key.substring(0, colon)];
      if (placement == null) {
        _fields.invalid(
          'The parameter key "$key" has no valid "in" before ":".',
          at,
          fix:
              'Write in:name with in one of '
              '${ParameterLocation.values.map((l) => l.name).join(', ')}.',
        );
        return null;
      }
      name = key.substring(colon + 1);
    }
    return ParameterOverride(
      key: key,
      pointer: at,
      parameterName: name,
      placement: placement,
      reason: _fields.string(entry, 'reason', at),
      spec: {
        if (entry.containsKey('required'))
          'required': ?_fields.boolean(entry, 'required', at),
        if (entry.containsKey('schema'))
          'schema': ?_fields.map(entry, 'schema', at),
      },
      name: _fields.string(entry, 'name', at),
      dartType: _generation.dartType(entry, at),
    );
  }

  BodyOverride _body(Map<String, Object?> entry, JsonPointer at) {
    _fields.checkKeys(entry, OverrideKeys.requestBody, at);
    return BodyOverride(
      key: 'requestBody',
      pointer: at,
      reason: _fields.string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  ResponseOverride _response(
    String status,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _fields.checkKeys(entry, OverrideKeys.response, at);
    return ResponseOverride(
      key: status,
      pointer: at,
      reason: _fields.string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  Map<String, Object?> _contentSpec(
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    final contentType = _fields.string(entry, 'contentType', at);
    if (contentType != null && !contentType.contains('/')) {
      _fields.invalid(
        '"contentType" must be a media type such as application/json.',
        at.child('contentType'),
      );
    }
    return {
      if (contentType != null && contentType.contains('/'))
        'contentType': contentType,
      if (entry.containsKey('schema'))
        'schema': ?_fields.map(entry, 'schema', at),
    };
  }
}
