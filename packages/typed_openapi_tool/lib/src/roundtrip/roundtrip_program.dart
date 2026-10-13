import 'package:typed_openapi/typed_openapi.dart';

/// The Dart program that round-trips the samples of one generated client:
/// each value goes through `fromJson`, `toJson`, JSON text and `fromJson`
/// again, and the second result must equal the first (spec decision 3).
///
/// The program reads the samples from the file its argument names and
/// prints one JSON object: `examples` and `synthetic` (the values that
/// decoded), `defects` (examples that do not decode: defects of the spec)
/// and `failures` (everything else that went wrong). Every import is
/// prefixed, so no generated name can clash with the program's.
final class RoundTripProgram {
  /// Creates the program for the declarations of [ir].
  const RoundTripProgram(this._ir);

  final ClientIr _ir;

  /// The source of the program, which imports the models of the client from
  /// [library] (`package:corpus_raw/stripe/models.dart`).
  String source(String library) {
    final codecs = StringBuffer();
    for (final d in _ir.declarations) {
      final decode = switch (d) {
        ModelDecl() => '(j) => m.${d.name}.fromJson(rt.JsonReader.asObject(j))',
        EnumDecl() || UnionDecl() => 'm.${d.name}.fromJson',
      };
      codecs.writeln(
        "  '${d.name}': (decode: $decode, "
        'encode: (v) => (v as m.${d.name}).toJson()),',
      );
    }
    return '''
// The round trip of a corpus client, written by the corpus tool.
import 'dart:convert' as convert;
import 'dart:io' as io;

import '$library' as m;
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart' as rt;

typedef RoundTripCodec = ({
  Object? Function(Object?) decode,
  Object? Function(Object?) encode,
});

final codecs = <String, RoundTripCodec>{
$codecs};

$_main''';
  }

  static const _main = r'''
void main(List<String> args) {
  final samples = convert.jsonDecode(io.File(args.single).readAsStringSync());
  var examples = 0;
  var synthetic = 0;
  final defects = <String>[];
  final failures = <String>[];
  for (final sample in (samples as List<Object?>).cast<Map<String, Object?>>()) {
    final type = sample['type'] as String;
    final isExample = sample['example'] == true;
    final value = sample['value'];
    final codec = codecs[type]!;
    final Object? first;
    try {
      first = codec.decode(value);
    } on rt.JsonDecodeException catch (e) {
      (isExample ? defects : failures).add('$type: $e');
      continue;
    } on FormatException catch (e) {
      (isExample ? defects : failures).add('$type: $e');
      continue;
    } catch (e) {
      failures.add('$type: decoding ${convert.jsonEncode(value)} threw $e');
      continue;
    }
    isExample ? examples++ : synthetic++;
    try {
      final text = convert.jsonEncode(codec.encode(first));
      final second = codec.decode(convert.jsonDecode(text));
      if (second != first) {
        failures.add('$type: ${convert.jsonEncode(value)} came back as $text');
      }
    } catch (e) {
      failures.add('$type: the round trip of ${convert.jsonEncode(value)} threw $e');
    }
  }
  io.stdout.writeln(convert.jsonEncode({
    'examples': examples,
    'synthetic': synthetic,
    'defects': defects,
    'failures': failures,
  }));
}
''';
}
