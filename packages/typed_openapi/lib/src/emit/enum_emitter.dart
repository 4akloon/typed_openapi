import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'model_emitter.dart';
import 'type_codec.dart';

/// Writes an [EnumDecl] as an open enum (decision 9 of M8, research §C.3):
/// a `sealed` class (an `abstract interface` one when the enum is not
/// exhaustive) with a static alias per value, a Dart `enum` of the known
/// values that implements it, and a class for a value the spec does not
/// list, which keeps the raw value (R8.1) and only `fromJson` creates.
final class EnumEmitter {
  /// Creates an emitter that writes with [_codec].
  const EnumEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes [decl] to [out].
  void write(EnumDecl decl, DartWriter out) {
    final name = decl.name;
    final known = decl.knownName;
    final unknown = decl.unknownName;
    final (type, read) = switch (decl.kind) {
      .string => ('String', 'asString'),
      .integer => ('int', 'asInt'),
      .number => ('num', 'asNumber'),
      .boolean => ('bool', 'asBool'),
    };
    _codec.imports.fromRuntime('JsonReader');
    out.doc(decl.description);
    if (decl.deprecated) out.line(ModelEmitter.deprecation);
    final modifier = decl.exhaustive ? 'sealed' : 'abstract interface';
    out.block('$modifier class $name', () {
      out
        ..line('/// Decodes a [$name]; a value the spec does not list is a')
        ..line('/// [$unknown].')
        ..block('factory $name.fromJson(Object? json)', () {
          out.line('final value = JsonReader.$read(json);');
          out.block('for (final known in $known.values)', () {
            out.line('if (known.value == value) return known;');
          });
          out.line('return $unknown._(value);');
        });
      for (final value in decl.values) {
        out.line();
        _valueDoc(out, value);
        out.line('static const ${value.name} = $known.${value.name};');
      }
      out
        ..line()
        ..line('/// The value in JSON.')
        ..line('$type get value;')
        ..line()
        ..line('/// The value in JSON.')
        ..line('$type toJson();');
    });
    out
      ..line()
      ..line('/// The values of [$name] the spec lists.')
      ..block('enum $known implements $name', () {
        for (final (i, value) in decl.values.indexed) {
          if (i > 0) out.line();
          _valueDoc(out, value);
          final last = i == decl.values.length - 1;
          out.line(
            '${value.name}(${_code.literal(value.value)})${last ? ';' : ','}',
          );
        }
        out
          ..line()
          ..line('const $known(this.value);')
          ..line()
          ..line('@override')
          ..line('final $type value;')
          ..line()
          ..line('@override')
          ..line('$type toJson() => value;');
      });
    out
      ..line()
      ..line('/// A value of [$name] the spec does not list; only')
      ..line('/// [$name.fromJson] creates one.')
      ..block('class $unknown implements $name', () {
        out
          ..line('const $unknown._(this.value);')
          ..line()
          ..line('@override')
          ..line('final $type value;')
          ..line()
          ..line('@override')
          ..line('$type toJson() => value;')
          ..line()
          ..line('@override')
          ..line('bool operator ==(Object other) =>')
          ..indented(
            () => out.indented(
              () => out.line('other is $unknown && other.value == value;'),
            ),
          )
          ..line()
          ..line('@override')
          ..line('int get hashCode => value.hashCode;')
          ..line()
          ..line('@override')
          ..line(
            "String toString() => '${unknown.replaceAll(r'$', r'\$')}"
            r"($value)';",
          );
      });
  }

  void _valueDoc(DartWriter out, EnumValueIr value) {
    out.doc(
      value.description ?? '`${_code.docSpan(_code.literal(value.value))}`',
    );
  }
}
