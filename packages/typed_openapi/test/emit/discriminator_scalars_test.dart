import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/emit_fixture.dart';
import 'discriminator_array_test.dart' show fromJsonOf;

void main() {
  for (final mode in UnionMode.values) {
    group('a discriminator union with scalar variants ($mode)', () {
      late Map<String, String> files;
      setUpAll(() {
        files = emitFixture(
          'discriminator_scalars.yaml',
          generation: GenerationConfig(union: mode),
        );
      });

      test('picks int before num, whatever the order of the variants', () {
        final factory = fromJsonOf(files, 'Value');
        final int = factory.indexOf('if (json case final int value)');
        final number = factory.indexOf('if (json case final num value)');
        expect(int, greaterThan(0));
        expect(number, greaterThan(int));
      });

      test('the first variant of a JSON type wins', () {
        final factory = fromJsonOf(files, 'Value');
        expect(
          RegExp('case final String value').allMatches(factory),
          hasLength(1),
        );
        expect(factory, contains('return ValueString(JsonReader.asString('));
        expect(factory, isNot(contains('ValueColor(')));
      });

      test('a default mapping is the last case, with the value kept', () {
        expect(
          fromJsonOf(files, 'Defaulted'),
          contains(
            '_ => DefaultedDog(Dog.fromJson(JsonReader.asObject(r.json)))',
          ),
        );
        expect(
          fromJsonOf(files, 'Bare'),
          contains('final tag => BarePlain._('),
        );
      });
    });
  }
}
