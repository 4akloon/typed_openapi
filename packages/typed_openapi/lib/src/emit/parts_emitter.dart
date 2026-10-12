import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the class of the parts of a multipart body (R10.4): a field per
/// part, `FileUpload` for files, and `toParts()`.
final class PartsEmitter {
  /// Creates an emitter that writes with [_codec].
  const PartsEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes the class [name] of the parts of [operation] of [group].
  void write(
    DartWriter out,
    String name,
    OperationIr operation,
    GroupIr group,
  ) {
    final parts = operation.body!.parts!;
    _codec.imports
      ..fromRuntime('MultipartPart')
      ..fromRuntime('immutable');
    out
      ..prose(
        'The parts of the `multipart/form-data` body of '
        '[${group.name}.${operation.name}].',
      )
      ..line('@immutable')
      ..block('class $name', () {
        out
          ..prose('Creates the parts.')
          ..list('const $name({', [
            for (final p in parts)
              '${p.required ? 'required ' : ''}this.${p.name}',
          ], '});');
        for (final part in parts) {
          out.line();
          out.doc(part.description);
          out.line('final ${_partType(part.type)} ${part.name};');
        }
        out
          ..line()
          ..prose('The parts, in the order of the schema.')
          ..line('List<MultipartPart> toParts() => [');
        out.indented(() {
          for (final part in parts) {
            out.line('${_part(part)},');
          }
        });
        out.line('];');
      });
  }

  /// The Dart type of a part: a binary string is a `FileUpload`, also as
  /// the items of a list.
  String _partType(DartType type) {
    final mark = type.nullable ? '?' : '';
    if (_isFile(type)) {
      _codec.imports.fromRuntime('FileUpload');
      return 'FileUpload$mark';
    }
    if (type case ListType(:final item) when _isFile(item)) {
      _codec.imports.fromRuntime('FileUpload');
      return 'List<FileUpload${item.nullable ? '?' : ''}>$mark';
    }
    return _codec.known(type);
  }

  static bool _isFile(DartType type) =>
      type is CoreType && type.kind == CoreKind.binary;

  String _part(PartIr part) {
    final wire = _code.string(part.wireName);
    final type = part.type;
    final contentType = part.contentType == null
        ? ''
        : ', contentType: ${_code.string(part.contentType!)}';
    if (_isFile(type)) {
      return type.nullable
          ? 'if (${part.name} case final file?) '
                'MultipartPart.file($wire, file$contentType)'
          : 'MultipartPart.file($wire, ${part.name}$contentType)';
    }
    if (type case ListType(:final item) when _isFile(item)) {
      final files = type.nullable ? '...?${part.name}' : '...${part.name}';
      return 'for (final file in [$files]) '
          '${item.nullable ? 'if (file != null) ' : ''}'
          'MultipartPart.file($wire, file$contentType)';
    }
    return 'MultipartPart.value($wire, '
        '${_codec.encodeNullable(type, part.name)}$contentType)';
  }
}
