import '../ir/dart_type.dart';
import '../ir/ir.dart';
import '../ir/names.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'decoder_writer.dart';
import 'event_stream_writer.dart';
import 'event_union_emitter.dart';
import 'parts_emitter.dart';
import 'request_writer.dart';
import 'status_type_emitter.dart';
import 'type_codec.dart';

/// Writes the class of a [GroupIr] (decisions 1–3, 5–10 of M9): a plain
/// class, so `implements` mocks it (R10.7), with a method per operation that
/// builds an `OperationRequest` and sends it through `DioRequestSender`;
/// then the sealed types of the operations' statuses and the classes of
/// their multipart parts. [RequestWriter] writes the request,
/// [DecoderWriter] the decoder, [StatusTypeEmitter] and [PartsEmitter] the
/// types.
///
/// Every argument is named and the last one is `CallOptions? call`; a
/// method returns `Future<Result<T, E>>` and never throws for a response.
final class OperationEmitter {
  /// Creates an emitter that writes with [codec].
  OperationEmitter(TypeCodec codec) : this._(codec, DecoderWriter(codec));

  OperationEmitter._(this._codec, this._decoder)
    : _request = RequestWriter(_codec),
      _events = EventStreamWriter(_decoder);

  final TypeCodec _codec;
  final RequestWriter _request;
  final DecoderWriter _decoder;
  final EventStreamWriter _events;

  static const _code = DartCode();
  static const _names = DartNames();

  /// The runtime library generated code imports.
  static const _dio = 'package:dio/dio.dart';

  /// Writes [group] and the types of its operations to [out].
  void write(GroupIr group, DartWriter out) {
    final name = group.name;
    _codec.imports
      ..show(_dio, 'Dio')
      ..fromRuntime('DioRequestSender');
    final members = _privateNames(group);
    out.prose('The operations of the `${_code.docSpan(name)}` group.');
    out.block('class $name', () {
      out
        ..prose('Sends the requests through [dio], which it uses as it is.')
        ..line('$name(Dio dio) : _sender = DioRequestSender(dio);')
        ..line()
        ..line('final DioRequestSender _sender;');
      for (final (operation, info, _) in members) {
        out.line();
        _info(out, operation, info);
      }
      for (final (operation, info, decoder) in members) {
        out.line();
        _method(out, operation, info, decoder);
        out.line();
        _decoder.write(out, operation, decoder);
      }
    });
    _types(out, group);
  }

  /// Writes the sealed status types and the parts classes of the
  /// operations of [group], after the group's class.
  void _types(DartWriter out, GroupIr group) {
    for (final operation in group.operations) {
      for (final (type, what) in [
        (operation.successType, 'successes'),
        (operation.errorType, 'errors'),
      ]) {
        if (type == null) continue;
        out.line();
        StatusTypeEmitter(_codec).write(out, type, operation, group, what);
      }
      if (operation.partsName case final parts?) {
        out.line();
        PartsEmitter(_codec).write(out, parts, operation, group);
      }
      if (operation.events?.union case final union?) {
        out.line();
        EventUnionEmitter(_codec).write(out, union, operation, group);
      }
    }
  }

  /// The private members of [group]'s class: an `OperationInfo` and a
  /// decoder per operation, named apart from each other and from the
  /// sender.
  static List<(OperationIr, String, String)> _privateNames(GroupIr group) {
    final private = NameScope(reserved: const {}, reservedSuffix: '')
      ..reserve('_sender');
    return [
      for (final operation in group.operations)
        (
          operation,
          private.claim('_${operation.name}').$1,
          private.claim('_decode${_names.pascal(operation.name)}').$1,
        ),
    ];
  }

  void _info(DartWriter out, OperationIr operation, String info) {
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

  void _method(
    DartWriter out,
    OperationIr operation,
    String info,
    String decoder,
  ) {
    _codec.imports
      ..fromRuntime('Result')
      ..fromRuntime('CallOptions')
      ..fromRuntime('OperationRequest');
    _doc(out, operation);
    if (operation.deprecated) {
      out.line("@Deprecated('Deprecated in the API spec.')");
    }
    out.list(
      'Future<Result<${_decoder.successType(operation)}, '
      '${_decoder.errorType(operation)}>> '
      '${operation.name}({',
      _arguments(operation),
      operation.events == null
          ? '}) => _sender.send('
          : '}) => _sender.openEvents(',
    );
    out.indented(() => _send(out, operation, info, decoder));
    out.line(');');
  }

  /// The named arguments of the method of [operation]: its parameters, the
  /// body and `call`.
  List<String> _arguments(OperationIr operation) => [
    for (final parameter in operation.parameters)
      _argument(
        _codec.known(parameter.type),
        parameter.name,
        isRequired: parameter.required,
        type: parameter.type,
      ),
    if (_request.bodyType(operation) case final body?)
      _argument(
        body,
        'body',
        isRequired: operation.body!.required,
        type: operation.partsName == null ? operation.body!.type : null,
      ),
    'CallOptions? call',
  ];

  /// The arguments of `_sender.send`: the request, the decoder and `call`.
  void _send(
    DartWriter out,
    OperationIr operation,
    String info,
    String decoder,
  ) {
    out.line('OperationRequest(');
    out.indented(() {
      out.line('$info,');
      _request.parameters(out, operation);
      _request.body(out, operation);
      final kind = DecoderWriter.responseKind(operation);
      if (kind != 'json') out.line('responseKind: .$kind,');
      if (operation.accept case final accept?) {
        out.line('accept: ${_code.string(accept)},');
      }
      if (operation.events != null) _events.statuses(out, operation);
    });
    out.line('),');
    if (operation.events case final events?) {
      out.line('${_events.decoder(events)},');
    }
    out
      ..line('$decoder,')
      ..line('call: call,');
    if (operation.events case final events?) _events.reconnection(out, events);
  }

  /// The declaration of a named argument of the Dart type [declared]:
  /// `required` when it is, and `JsonValue` (a [type] of kind json), which
  /// is never nullable, defaults to JSON `null` when it is optional.
  static String _argument(
    String declared,
    String name, {
    required bool isRequired,
    DartType? type,
  }) {
    if (isRequired) return 'required $declared $name';
    if (type case CoreType(kind: .json)) {
      return '$declared $name = const JsonValue(null)';
    }
    return '$declared $name';
  }

  /// The doc comment of a method: summary, description, method and path,
  /// and the parameters that have a description or a default.
  void _doc(DartWriter out, OperationIr operation) {
    out.doc(operation.summary);
    if (operation.summary != null && operation.description != null) {
      out.line('///');
    }
    out.doc(operation.description);
    if (operation.summary != null || operation.description != null) {
      out.line('///');
    }
    if (operation.events case final events?) {
      out
        ..prose(_events.doc(events))
        ..line('///');
    }
    out.prose(
      '`${_code.docSpan('${operation.method} ${operation.path}')}`'
      '${operation.operationId == null ? '' : ' '
                '(`${_code.docSpan(operation.operationId!)}`)'}.',
    );
    for (final parameter in operation.parameters) {
      // A required parameter is always sent: its default is never used.
      final defaultValue = parameter.required ? null : parameter.defaultValue;
      if (parameter.description == null && defaultValue == null) continue;
      out
        ..line('///')
        ..prose(
          '[${parameter.name}]'
          '${parameter.deprecated ? ' (deprecated)' : ''}'
          '${defaultValue == null ? '' : ', when not sent, is '
                    '${_code.jsonSpan(defaultValue.$1)} on the server'}'
          '${parameter.description == null ? '.' : ':'}',
        )
        ..doc(parameter.description);
    }
  }
}
