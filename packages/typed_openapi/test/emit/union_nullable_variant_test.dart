import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';

/// The `toJson` line of the class [name] in the files [files].
String toJsonOf(Map<String, String> files, String name) {
  final source = files.values.join('\n');
  final start = source.indexOf('class $name ');
  if (start < 0) throw StateError('no class $name');
  final end = source.indexOf('Object? toJson()', start);
  if (end < 0) throw StateError('no toJson in class $name');
  return source.substring(end, source.indexOf('\n', end));
}

void main() {
  for (final mode in UnionMode.values) {
    test('a nullable variant binds its value before it encodes it ($mode)', () {
      final files = emitFixture(
        'nullable_variants.yaml',
        generation: GenerationConfig(union: mode),
      );
      expect(
        toJsonOf(files, 'ValueList'),
        'Object? toJson() => switch (value) {final v? => '
        '[for (final e0 in v) e0.toJson()], null => null};',
      );
      expect(
        toJsonOf(files, 'ValueMap'),
        'Object? toJson() => value?.map((k0, v0) => MapEntry(k0, v0.toJson()));',
      );
      expect(toJsonOf(files, 'ValueString'), 'Object? toJson() => value;');
    });
  }
}
