import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/emit_fixture.dart';

/// The `fromJson` factory of the class [name] in the files [files].
String fromJsonOf(Map<String, String> files, String name) {
  final source = files.values.join('\n');
  final start = source.indexOf('factory $name.fromJson');
  if (start < 0) throw StateError('no $name.fromJson');
  return source.substring(start, source.indexOf('\n  }\n', start));
}

void main() {
  for (final mode in UnionMode.values) {
    test('a non-object variant is picked by JSON type first ($mode)', () {
      final factory = fromJsonOf(
        emitFixture(
          'discriminator_array.yaml',
          generation: GenerationConfig(union: mode),
        ),
        'Content',
      );
      final byType = factory.indexOf(
        'if (json case final List<Object?> value)',
      );
      expect(byType, greaterThan(0));
      expect(
        factory,
        contains(
          'return ContentList(JsonReader.listOf('
          'JsonReader.objectOf(Item.fromJson))(value));',
        ),
      );
      expect(byType, lessThan(factory.indexOf('JsonReader.of(json')));
      expect(factory, isNot(contains("'array' =>")));
      expect(factory, contains("'file' => ContentFile("));
    });
  }
}
