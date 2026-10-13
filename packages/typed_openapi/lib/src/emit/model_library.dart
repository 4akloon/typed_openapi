import '../ir/dart_type.dart';
import '../ir/ir.dart';
import '../ir/names.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'enum_emitter.dart';
import 'imports.dart';
import 'model_emitter.dart';
import 'type_codec.dart';
import 'union_emitter.dart';

/// The model files of a client (decision 2 of M8): one file per declaration
/// in `models/`, named after the declaration in snake case, and the barrel
/// `models.dart` that exports them.
///
/// Files import each other by relative paths. Two declarations whose names
/// give the same file name, which also happens on file systems that ignore
/// case (`UserDTO`, `UserDto`), get `2`, `3`, ... in the order of their
/// names. Every file starts with [header].
final class ModelLibrary {
  /// Creates the library writer; lines are wrapped at [width].
  const ModelLibrary({this.width = 80});

  /// The line width.
  final int width;

  /// The first lines of every generated file.
  static const header =
      '// GENERATED CODE - DO NOT MODIFY BY HAND.\n// dart format off\n';

  /// The directory of the model files, relative to the output directory.
  static const directory = 'models';

  /// The barrel file, relative to the output directory.
  static const barrel = 'models.dart';

  static const _names = DartNames();

  /// The files of [ir] by path relative to the output directory, sorted by
  /// path.
  Map<String, String> files(ClientIr ir) {
    final fileNames = this.fileNames(ir);
    final files = <String, String>{};
    for (final declaration in ir.declarations) {
      final file = fileNames[declaration.id]!;
      final imports = Imports(file);
      final codec = TypeCodec(ir, imports, (id) => fileNames[id]!);
      final body = DartWriter(width);
      switch (declaration) {
        case final ModelDecl model:
          ModelEmitter(codec).write(model, body);
        case final EnumDecl decl:
          EnumEmitter(codec).write(decl, body);
        case final UnionDecl decl:
          UnionEmitter(codec).write(decl, body);
      }
      final out = DartWriter(width);
      writeHeader(out);
      imports.write(out);
      files['$directory/$file'] = '${out.text}${body.text}';
    }
    final exports = DartWriter(width);
    writeHeader(exports);
    final paths = files.keys.toList()..sort();
    for (final path in paths) {
      exports.line('export ${_code.string(path)};');
    }
    files[barrel] = exports.text;
    return {for (final path in files.keys.toList()..sort()) path: files[path]!};
  }

  /// The file name of every declaration of [ir], without the directory.
  Map<DeclId, String> fileNames(ClientIr ir) {
    final scope = NameScope(reserved: const {}, reservedSuffix: '');
    return {
      for (final declaration in ir.declarations)
        declaration.id: '${scope.claim(snake(declaration.name)).$1}.dart',
    };
  }

  /// [name] in lower snake case; a name that does not start with a letter
  /// gets `type_` in front, as Dart file names must.
  static String snake(String name) {
    final snake = _names.words(name).map((w) => w.toLowerCase()).join('_');
    return snake.startsWith(RegExp('[a-z]')) ? snake : 'type_$snake';
  }

  static const _code = DartCode();

  /// Writes [header] and an empty line.
  static void writeHeader(DartWriter out) {
    header.trimRight().split('\n').forEach(out.line);
    out.line();
  }
}
