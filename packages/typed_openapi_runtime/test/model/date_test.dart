import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  const invalid = [
    '2024-2-3',
    '2024-02-30',
    '2023-02-29',
    '2024-02-03T00:00:00Z',
    ' 2024-02-03',
    '2024/02/03',
    '+2024-02-03',
    '20240203',
    '',
    '2024-02-03\n',
  ];

  group('Date constructor', () {
    test('accepts a leap day', () {
      final date = Date(2024, 2, 29);
      expect([date.year, date.month, date.day], [2024, 2, 29]);
      expect(Date(0, 1, 1).year, 0);
      expect(Date(9999, 12, 31).day, 31);
    });

    test('rejects dates that do not exist', () {
      expect(() => Date(2023, 2, 29), throwsArgumentError);
      expect(() => Date(2024, 13, 1), throwsArgumentError);
      expect(() => Date(2024, 0, 1), throwsArgumentError);
      expect(() => Date(2024, 4, 31), throwsArgumentError);
      expect(() => Date(2024, 1, 0), throwsArgumentError);
      expect(() => Date(-1, 1, 1), throwsArgumentError);
      expect(() => Date(10000, 1, 1), throwsArgumentError);
    });
  });

  group('parse and format', () {
    test('parse reads YYYY-MM-DD', () {
      final date = Date.parse('2024-02-03');
      expect([date.year, date.month, date.day], [2024, 2, 3]);
      expect(date.toJson(), '2024-02-03');
      expect(date.toString(), '2024-02-03');
    });

    test('toJson zero-pads every field', () {
      expect(Date(5, 1, 9).toJson(), '0005-01-09');
    });

    test('parse rejects other text with a FormatException', () {
      for (final text in invalid) {
        expect(
          () => Date.parse(text),
          throwsFormatException,
          reason: text,
        );
      }
    });

    test('tryParse returns null for invalid text and a Date otherwise', () {
      for (final text in invalid) {
        expect(Date.tryParse(text), isNull, reason: text);
      }
      expect(Date.tryParse('2024-02-29'), Date(2024, 2, 29));
    });

    test('round trips', () {
      for (final date in [
        Date(0, 1, 1),
        Date(9999, 12, 31),
        Date(2024, 2, 29),
      ]) {
        expect(Date.parse(date.toJson()), date);
      }
    });
  });

  group('conversions', () {
    test('fromDateTime keeps the fields of the own time zone', () {
      expect(
        Date.fromDateTime(DateTime(2024, 2, 3, 23, 59)),
        Date(2024, 2, 3),
      );
      expect(
        Date.fromDateTime(DateTime.utc(2024, 2, 3, 0, 0)),
        Date(2024, 2, 3),
      );
    });

    test('toDateTimeUtc is midnight UTC', () {
      final dateTime = Date(2024, 2, 3).toDateTimeUtc();
      expect(dateTime, DateTime.utc(2024, 2, 3));
      expect(dateTime.isUtc, isTrue);
    });
  });

  group('equality and order', () {
    test('equal dates have equal hash codes', () {
      expect(Date(2024, 2, 3) == Date(2024, 2, 3), isTrue);
      expect(Date(2024, 2, 3).hashCode, Date(2024, 2, 3).hashCode);
    });

    test('a difference in any field makes dates unequal', () {
      final base = Date(2024, 2, 3);
      expect(base == Date(2025, 2, 3), isFalse);
      expect(base == Date(2024, 3, 3), isFalse);
      expect(base == Date(2024, 2, 4), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(base == '2024-02-03', isFalse);
    });

    test('compareTo orders by year, then month, then day', () {
      final sorted = [
        Date(2023, 12, 31),
        Date(2024, 1, 1),
        Date(2024, 1, 2),
        Date(2024, 2, 1),
        Date(2025, 1, 1),
      ];
      final shuffled = [sorted[3], sorted[0], sorted[4], sorted[2], sorted[1]];
      expect(shuffled..sort(), sorted);
      expect(Date(2024, 2, 3).compareTo(Date(2024, 2, 3)), 0);
    });

    test('isBefore and isAfter', () {
      final a = Date(2024, 2, 3);
      final b = Date(2024, 2, 4);
      expect(a.isBefore(b), isTrue);
      expect(a.isAfter(b), isFalse);
      expect(b.isAfter(a), isTrue);
      expect(b.isBefore(a), isFalse);
      expect(a.isBefore(Date(2024, 2, 3)), isFalse);
      expect(a.isAfter(Date(2024, 2, 3)), isFalse);
    });
  });
}
