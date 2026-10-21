import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the `OperationInfo` constant of an operation: its id, method,
/// path, tags and security alternatives, which every request carries to the
/// transport.
final class OperationInfoWriter {
  /// Creates a writer that records its imports in [codec].
  OperationInfoWriter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes the constant [info] describing [operation] to [out].
  void write(DartWriter out, OperationIr operation, String info) {
    _codec.imports.fromRuntime('OperationInfo');
    out.line('static const $info = OperationInfo(');
    out.indented(() {
      out
        ..line(
          'operationId: '
          '${_code.string(operation.operationId ?? operation.name)},',
        )
        ..line('method: ${_code.string(operation.method)},')
        ..line('pathTemplate: ${_code.string(operation.path)},');
      if (operation.tags.isNotEmpty) {
        out.list('tags: [', [
          for (final tag in operation.tags) _code.string(tag),
        ], '],');
      }
      if (operation.security.isNotEmpty) {
        out.line('security: [');
        out.indented(() {
          for (final alternative in operation.security) {
            out.list('[', [for (final use in alternative) _use(use)], '],');
          }
        });
        out.line('],');
      }
    });
    out.line(');');
  }

  String _use(SecurityUseIr use) {
    _codec.imports
      ..fromRuntime('SecurityUse')
      ..fromRuntime('SecurityScheme');
    final scheme = use.scheme;
    final arguments = [
      _code.string(scheme.name),
      '.${scheme.kind.name}',
      if (scheme.parameterName case final v?)
        'parameterName: ${_code.string(v)}',
      if (scheme.placement case final v?) 'location: .$v',
      if (scheme.scheme case final v?) 'scheme: ${_code.string(v)}',
      if (scheme.bearerFormat case final v?) 'bearerFormat: ${_code.string(v)}',
      if (scheme.openIdConnectUrl case final v?)
        'openIdConnectUrl: ${_code.string(v)}',
    ];
    final scopes = use.scopes.isEmpty
        ? ''
        : ', [${use.scopes.map(_code.string).join(', ')}]';
    return 'SecurityUse(SecurityScheme(${arguments.join(', ')})$scopes)';
  }
}
