import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/dart_code.dart';

/// The implicit directional marks: U+200E, U+200F and U+061C.
const _marks = {0x200e: 'LRM', 0x200f: 'RLM', 0x061c: 'ALM'};

void main() {
  const code = DartCode();

  for (final MapEntry(key: unit, value: name) in _marks.entries) {
    final mark = String.fromCharCode(unit);
    final hex = unit.toRadixString(16);

    group('the $name mark (U+${hex.toUpperCase()})', () {
      test('is escaped in a string literal', () {
        expect(code.string('a${mark}b'), "'a\\u{$hex}b'");
      });

      test('is dropped from a doc comment line', () {
        expect(code.docLines('a${mark}b', 80), ['ab']);
      });

      test('is dropped from a code span', () {
        expect(code.docSpan('a${mark}b'), 'ab');
        expect(code.jsonSpan('a${mark}b'), '`"ab"`');
      });
    });
  }
}
