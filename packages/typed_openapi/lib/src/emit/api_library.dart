import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'model_library.dart';
import 'operation_emitter.dart';
import 'type_codec.dart';

/// The files of a whole client (decision 4 of M9): the models of
/// [ModelLibrary], a file per group in `api/` with the barrel `api.dart`,
/// and the root client in `<client>.dart`, which exports both barrels.
///
/// Group files are named after their class in snake case, in their own
/// directory and name scope, so they never move a model file.
final class ApiLibrary {
  /// Creates the library writer; lines are wrapped at [width].
  const ApiLibrary({this.width = 80});

  /// The line width.
  final int width;

  /// The directory of the group files, relative to the output directory.
  static const directory = 'api';

  /// The barrel of the group files, relative to the output directory.
  static const barrel = 'api.dart';

  static const _code = DartCode();
  static const _names = DartNames();

  /// The files of [ir], the IR of the client [client], by path relative to
  /// the output directory, sorted by path.
  Map<String, String> files(ClientIr ir, {required String client}) {
    final models = ModelLibrary(width: width);
    final modelFiles = models.fileNames(ir);
    final files = models.files(ir);
    final groupFiles = fileNames(ir);
    for (final group in ir.groups) {
      final file = groupFiles[group.name]!;
      final imports = Imports(file);
      final codec = TypeCodec(
        ir,
        imports,
        (id) => '../${ModelLibrary.directory}/${modelFiles[id]}',
      );
      final body = DartWriter(width);
      OperationEmitter(codec).write(group, body);
      final out = DartWriter(width);
      ModelLibrary.writeHeader(out);
      imports.write(out);
      files['$directory/$file'] = '${out.text}${body.text}';
    }
    final exports = DartWriter(width);
    ModelLibrary.writeHeader(exports);
    for (final group
        in ir.groups.map((g) => groupFiles[g.name]!).toList()..sort()) {
      exports.line('export ${_code.string('$directory/$group')};');
    }
    files[barrel] = exports.text;
    files[rootFile(client)] = _root(ir, groupFiles);
    return {for (final path in files.keys.toList()..sort()) path: files[path]!};
  }

  /// The file name of every group of [ir], by class name, without the
  /// directory.
  Map<String, String> fileNames(ClientIr ir) {
    final scope = NameScope(reserved: const {}, reservedSuffix: '');
    return {
      for (final group in ir.groups)
        group.name: '${scope.claim(ModelLibrary.snake(group.name)).$1}.dart',
    };
  }

  /// The file of the root client [client]: its name in snake case, or with
  /// `_client` when that would be a barrel's name.
  static String rootFile(String client) {
    final snake = ModelLibrary.snake(_names.pascal(client) ?? 'api');
    return switch ('$snake.dart') {
      ModelLibrary.barrel || barrel => '${snake}_client.dart',
      final file => file,
    };
  }

  String _root(ClientIr ir, Map<String, String> groupFiles) {
    final root = ir.root;
    final imports = Imports(rootFile(root.name))
      ..fromRuntime('CallOptions')
      ..fromRuntime('ClientTransport');
    for (final group in ir.groups) {
      imports.file('$directory/${groupFiles[group.name]}');
    }
    final out = DartWriter(width);
    ModelLibrary.writeHeader(out);
    imports.write(out);
    out
      ..line('export ${_code.string(barrel)};')
      ..line('export ${_code.string(ModelLibrary.barrel)};')
      ..line()
      ..prose(
        'The client of the API: a field for each group of operations, and '
        'the servers of the spec. The transport sets the base URL.',
      )
      ..block('class ${root.name}', () {
        _constructor(out, ir);
        for (final group in ir.groups) {
          out
            ..line()
            ..prose('The operations of [${group.name}].')
            ..line('final ${group.name} ${group.field};');
        }
        for (final server in root.servers) {
          out.line();
          _server(out, server);
        }
      });
    return out.text;
  }

  /// The constructor of the root client: a group per field, each given the
  /// transport and the default call options.
  void _constructor(DartWriter out, ClientIr ir) {
    out.prose(
      'Creates the client: every group sends through [transport]. The '
      'options of each call win over [defaults], field by field.',
    );
    final initializers = [
      for (final group in ir.groups)
        '${group.field} = ${group.name}(transport, defaults: defaults)',
    ];
    const parameters =
        'ClientTransport transport, '
        '{CallOptions defaults = const CallOptions()}';
    final head = '${ir.root.name}($parameters)';
    final flat = initializers.isEmpty
        ? '$head;'
        : '$head : ${initializers.join(', ')};';
    if (out.indent.length + flat.length <= width) {
      out.line(flat);
      return;
    }
    out
      ..line('${ir.root.name}(')
      ..line('  ClientTransport transport, {')
      ..line('  CallOptions defaults = const CallOptions(),')
      ..line(initializers.isEmpty ? '});' : '})');
    out.indented(() {
      for (final (i, initializer) in initializers.indexed) {
        final last = i == initializers.length - 1;
        out.line('${i == 0 ? ': ' : '  '}$initializer${last ? ';' : ','}');
      }
    });
  }

  void _server(DartWriter out, ServerIr server) {
    out.prose('`${_code.docSpan(server.url)}`.');
    if (server.description != null) out.line('///');
    out.doc(server.description);
    if (server.variables.isEmpty) {
      out.line('static const ${server.name} = ${_code.string(server.url)};');
      return;
    }
    for (final variable in server.variables) {
      final values = variable.values;
      if (variable.description == null && values.isEmpty) continue;
      out
        ..line('///')
        ..prose(
          '[${variable.name}]'
          '${values.isEmpty ? '' : ', one of '
                    '${values.map(_code.jsonSpan).join(', ')}'}'
          '${variable.description == null ? '.' : ':'}',
        )
        ..doc(variable.description);
    }
    out.list('static String ${server.name}({', [
      for (final v in server.variables)
        if (v.defaultValue case final value?)
          'String ${v.name} = ${_code.string(value)}'
        else
          'required String ${v.name}',
    ], '}) =>');
    out.indented(() {
      out.indented(() {
        out.list('[', _pieces(server), '].join();');
      });
    });
  }

  /// The URL of [server] as the items of a list to join: literals and the
  /// arguments of its variables.
  static List<String> _pieces(ServerIr server) {
    final byName = {for (final v in server.variables) v.wireName: v};
    final pieces = <String>[];
    var start = 0;
    for (final match in PathTemplate(server.url).variables) {
      final variable = byName[match[1]];
      if (variable == null) continue;
      if (match.start > start) {
        pieces.add(_code.string(server.url.substring(start, match.start)));
      }
      pieces.add(variable.name);
      start = match.end;
    }
    if (start < server.url.length) {
      pieces.add(_code.string(server.url.substring(start)));
    }
    return pieces;
  }
}
