import '../ir/dart_type.dart';
import '../ir/ir.dart';
import '../model/media_type_name.dart';
import '../model/operation.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the request of an operation (R10.3, R10.4): its parameter lists
/// and its body, and the type of its `body` argument.
final class RequestWriter {
  /// Creates a writer that writes with [_codec].
  const RequestWriter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// The parameter lists of the request: the JSON form of each value, with
  /// its style when it is not the default.
  void parameters(DartWriter out, OperationIr operation) {
    for (final (placement, list, runtime) in [
      (ParameterLocation.path, 'path', 'PathParameter'),
      (ParameterLocation.query, 'query', 'QueryParameter'),
      (ParameterLocation.header, 'headers', 'HeaderParameter'),
      (ParameterLocation.cookie, 'cookies', 'CookieParameter'),
    ]) {
      final parameters = [
        for (final p in operation.parameters)
          if (p.placement == placement) p,
      ];
      if (parameters.isEmpty) continue;
      _codec.imports.fromRuntime(runtime);
      out.list('$list: [', [
        for (final p in parameters) _parameter(p, runtime),
      ], '],');
    }
  }

  String _parameter(ParameterIr parameter, String runtime) {
    final value = _json(parameter.type, parameter.name);
    final style = parameter.style;
    final options = [
      if (style != null &&
          style != .simple &&
          style != .form &&
          style != .cookie)
        'style: .${style.name}',
      if (parameter.explode case final explode?) 'explode: $explode',
      if (parameter.allowReserved && parameter.placement == .query)
        'allowReserved: true',
    ];
    final encoded = switch (parameter.contentType) {
      final type? when MediaTypeName(type).isJson => _jsonText(parameter),
      _ => value,
    };
    return '$runtime(${[_code.string(parameter.wireName), encoded, ...options].join(', ')})';
  }

  /// The JSON form of [name], a value of [type].
  String _json(DartType type, String name) => _codec.encodeNullable(type, name);

  /// The JSON text of a parameter with a JSON `content`; an absent value
  /// (`null`, also `JsonValue(null)`) is not sent.
  String _jsonText(ParameterIr parameter) {
    _codec.imports.show('dart:convert', 'jsonEncode');
    final ParameterIr(:name, :type) = parameter;
    if (type case CoreType(kind: .json)) {
      return '$name.isNull ? null : jsonEncode($name)';
    }
    if (!type.nullable) return 'jsonEncode(${_codec.encode(type, name)})';
    return '$name == null ? null : '
        'jsonEncode(${_codec.encode(type.withNullable(false), name)})';
  }

  /// The JSON form of the body inside its null check: an optional body is
  /// not `null` there.
  String _bodyJson(DartType type, {required bool isOptional}) => isOptional
      ? _codec.encode(type.withNullable(false), 'body')
      : _json(type, 'body');

  /// The type of the `body` argument; null without a body.
  String? bodyType(OperationIr operation) {
    final body = operation.body;
    if (body == null || body.kind == .none) return null;
    final mark = body.required ? '' : '?';
    if (operation.partsName case final parts?) return '$parts$mark';
    final type = body.type;
    if (type == null) return null;
    if (body.kind == .bytes) {
      _codec.imports.fromRuntime('FileUpload');
      return 'FileUpload$mark';
    }
    final shown = body.required ? type : type.withNullable(true);
    return _codec.known(shown);
  }

  /// Writes the body of the request and its `Content-Type`; nothing
  /// without a body.
  void body(DartWriter out, OperationIr operation) {
    final body = operation.body;
    if (bodyType(operation) == null) return;
    final value = _value(operation, body!);
    if (value == null) return;
    // An absent optional body has no `Content-Type`; a `null` body with one
    // is the JSON value `null`.
    final type = _code.string(_contentType(body));
    out
      ..line('body: $value,')
      ..line(
        body.required
            ? 'contentType: $type,'
            : 'contentType: body == null ? null : $type,',
      );
  }

  /// The expression of the body sent: `null` stays `null` for an optional
  /// body.
  String? _value(OperationIr operation, RequestBodyIr body) {
    final optional = !body.required;
    final type = body.type;
    final String value;
    switch (body.kind) {
      case .multipart when operation.partsName != null:
        _codec.imports.fromRuntime('MultipartBody');
        value = optional
            ? 'body == null ? null : MultipartBody(body.toParts())'
            : 'MultipartBody(body.toParts())';
      case .multipart:
        _codec.imports.fromRuntime('MultipartBody');
        final json = _bodyJson(type!, isOptional: optional);
        value = optional
            ? 'body == null ? null : MultipartBody.fromJson($json)'
            : 'MultipartBody.fromJson($json)';
      case .form:
        _codec.imports.fromRuntime('FormBody');
        final json = _bodyJson(type!, isOptional: optional);
        final encoding = [
          for (final e in body.encoding)
            if (_formEncoding(e) case final code?)
              '${_code.string(e.property)}: $code',
        ];
        final form = encoding.isEmpty
            ? 'FormBody($json)'
            : 'FormBody($json, {${encoding.join(', ')}})';
        value = optional ? 'body == null ? null : $form' : form;
      case .bytes || .text || .eventStream:
        value = 'body';
      case .json:
        value = _json(optional ? type!.withNullable(true) : type!, 'body');
      case .none:
        return null;
    }
    return value;
  }

  String? _formEncoding(EncodingIr encoding) {
    final arguments = [
      if (encoding.style case final style? when style != .form)
        'style: .${style.name}',
      if (encoding.explode case final explode?) 'explode: $explode',
      if (encoding.allowReserved) 'allowReserved: true',
      if (encoding.contentType case final type? when MediaTypeName(type).isJson)
        'json: true',
    ];
    if (arguments.isEmpty) return null;
    _codec.imports.fromRuntime('FormEncoding');
    return 'FormEncoding(${arguments.join(', ')})';
  }

  /// The `Content-Type` of a body: its media type, or a concrete one for a
  /// wildcard (`*/*`, `image/*`).
  static String _contentType(RequestBodyIr body) {
    final type = body.contentType!;
    if (!type.contains('*')) return type;
    return switch (body.kind) {
      .json => 'application/json',
      .text || .eventStream => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}
