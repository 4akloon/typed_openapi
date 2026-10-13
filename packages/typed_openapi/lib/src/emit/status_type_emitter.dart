import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes a sealed status type of an operation (decision 18 of M8): the
/// base, and a variant per status that wraps the body and is equal by value.
final class StatusTypeEmitter {
  /// Creates an emitter that writes with [_codec].
  const StatusTypeEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes [type], the sealed type of the [what] of [operation] of
  /// [group].
  void write(
    DartWriter out,
    StatusTypeIr type,
    OperationIr operation,
    GroupIr group,
    String what,
  ) {
    final method = '${group.name}.${operation.name}';
    out
      ..prose(
        'The $what of [$method], by status: a `switch` names every one.',
      )
      ..block('sealed class ${type.name}', () {
        out
          ..prose('Creates the value.')
          ..line('const ${type.name}();');
      });
    for (final variant in type.cases) {
      out
        ..line()
        ..prose(
          'The `${_code.docSpan(variant.status)}` response of [$method]'
          '${variant.type == null ? ', which has no body.' : '.'}',
        )
        ..block('class ${variant.name} extends ${type.name}', () {
          switch (variant.type) {
            case final body?:
              _withBody(out, variant, body);
            case null:
              _withoutBody(out, variant.name);
          }
        });
    }
  }

  static void _withoutBody(DartWriter out, String name) {
    out
      ..prose('Creates the value.')
      ..line('const $name();')
      ..line()
      ..line('@override')
      ..line('bool operator ==(Object other) => other is $name;')
      ..line()
      ..line('@override')
      ..line('int get hashCode => ($name).hashCode;')
      ..line()
      ..line('@override')
      ..line("String toString() => '${_code.escaped(name)}()';");
  }

  void _withBody(DartWriter out, StatusCaseIr variant, DartType body) {
    final name = variant.name;
    final deep = _codec.needsDeep(body);
    if (deep) _codec.imports.fromRuntime('DeepEquality');
    out
      ..prose('Wraps [body].')
      ..line('const $name(this.body);')
      ..line()
      ..prose('The body of the response.')
      ..line('final ${_codec.type(body)} body;')
      ..line()
      ..line('@override')
      ..chain('bool operator ==(Object other) =>', [
        'other is $name',
        if (deep)
          'const DeepEquality().equals(other.body, body)'
        else
          'other.body == body',
      ], '&&')
      ..line()
      ..line('@override')
      ..line(
        deep
            ? 'int get hashCode => const DeepEquality().hash(body);'
            : 'int get hashCode => body.hashCode;',
      )
      ..line()
      ..line('@override')
      ..line(
        "String toString() => '${_code.escaped(name)}(${_shown(variant)})';",
      );
  }

  /// What `toString` of [variant] writes for its body: `<redacted>` for a
  /// secret (the models do the same), a description for bytes, whose content
  /// is never printed, and the body for the rest, which prints itself.
  static String _shown(StatusCaseIr variant) {
    if (variant.sensitive) return '<redacted>';
    final type = variant.type;
    if (type is CoreType && (type.kind == .bytes || type.kind == .binary)) {
      return type.nullable
          ? r"${body == null ? 'null' : 'Uint8List(${body?.length})'}"
          : r'Uint8List(${body.length})';
    }
    return r'$body';
  }
}
