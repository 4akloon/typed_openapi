import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/test_platform.dart';

/// A model the way generated code reads one.
final class Tag {
  const Tag(this.name);

  factory Tag.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Tag');
    return Tag(r.required('name', JsonReader.asString));
  }

  final String name;
}

void main() {
  JsonDecodeException failure(void Function() body) {
    try {
      body();
    } on JsonDecodeException catch (e) {
      return e;
    }
    fail('expected a JsonDecodeException');
  }

  group('JsonReader properties', () {
    const json = <String, Object?>{
      'id': 7,
      'name': 'Rex',
      'tag': null,
      'extra': 'ignored',
    };
    const r = JsonReader(json, schema: 'Pet');

    test('reads valid properties and ignores undeclared ones', () {
      expect(r.required('id', JsonReader.asInt), 7);
      expect(r.requiredNullable('tag', JsonReader.asString), isNull);
      expect(r.requiredNullable('name', JsonReader.asString), 'Rex');
      expect(r.optional('name', JsonReader.asString), 'Rex');
      expect(r.optional('missing', JsonReader.asString), isNull);
    });

    test('a missing required property names schema, field and pointer', () {
      final e = failure(() => r.required('age', JsonReader.asInt));
      expect(e.schema, 'Pet');
      expect(e.field, 'age');
      expect(e.pointer, '/age');
      expect(e.message, 'expected a required property, got no value');
      expect(
        e.toString(),
        'JsonDecodeException: expected a required property, got no value '
        'at /age in Pet',
      );
      expect(
        failure(() => r.requiredNullable('age', JsonReader.asInt)).pointer,
        '/age',
      );
    });

    test('null is an error in a required non-nullable property only', () {
      final e = failure(() => r.required('tag', JsonReader.asString));
      expect(e.message, 'expected a non-null value, got null');
      expect(e.pointer, '/tag');
      // An optional property is T? in Dart: null reads as absent.
      expect(r.optional('tag', JsonReader.asString), isNull);
      expect(r.requiredNullable('tag', JsonReader.asString), isNull);
    });

    test('a wrong type names expected and actual JSON types', () {
      final e = failure(() => r.required('name', JsonReader.asInt));
      expect(e.message, 'expected an integer, got a string');
      expect(e.pointer, '/name');
    });

    test('any JSON value: null is a value, absent is not', () {
      expect(r.requiredValue('tag').isNull, isTrue);
      expect(r.requiredValue('name').asString, 'Rex');
      expect(failure(() => r.requiredValue('age')).pointer, '/age');
      expect(r.optionalValue('missing').isNull, isTrue);
      expect(r.optionalValue('tag').isNull, isTrue);
      expect(r.optionalValue('id').asNumber, 7);
    });

    test('patch distinguishes absent, null and a value', () {
      expect(r.patch('missing', JsonReader.asString), isNull);
      expect(
        r.patch('tag', JsonReader.asString),
        const Patch<String>.nullValue(),
      );
      expect(r.patch('name', JsonReader.asString), const Patch.value('Rex'));
    });

    test('JsonReader.of rejects a non-object with the schema name', () {
      final e = failure(() => JsonReader.of([1], schema: 'Pet'));
      expect(e.message, 'expected an object, got an array');
      expect(e.schema, 'Pet');
      expect(e.pointer, '');
      expect(JsonReader.of(json, schema: 'Pet').json, same(json));
    });
  });

  group('dynamic-keyed maps', () {
    // `Response(data: {})` and custom transformers give Map<dynamic, dynamic>.
    final Map<dynamic, dynamic> untyped = <dynamic, dynamic>{
      'name': 'Rex',
      'a': [1, 'x'],
    };

    test('a map with string keys is an object', () {
      expect(JsonReader.of(untyped, schema: 'Pet').json, {
        'name': 'Rex',
        'a': [1, 'x'],
      });
      expect(
        JsonReader.of(untyped, schema: 'Pet').required(
          'name',
          JsonReader.asString,
        ),
        'Rex',
      );
      expect(JsonReader.asObject(untyped)['name'], 'Rex');
      expect(JsonReader.asObject(<dynamic, dynamic>{}), isEmpty);
      final typed = <String, Object?>{'k': 1};
      expect(JsonReader.asObject(typed), same(typed));
      final value = JsonValue(untyped);
      expect(value.asObject?['name'], 'Rex');
      expect(value['name'].asString, 'Rex');
      expect(value['a'][1].asString, 'x');
    });

    test('a non-string key names the key', () {
      final bad = <dynamic, dynamic>{'a': 1, 2: 'b'};
      final e = failure(() => JsonReader.asObject(bad));
      expect(e.expected, 'an object');
      expect(e.actual, 'an object with a non-string key `2`');
      expect(
        failure(() => JsonReader.of(bad, schema: 'Pet')).schema,
        'Pet',
      );
      final value = JsonValue(bad);
      expect(value.asObject, isNull);
      expect(value['a'].isNull, isTrue);
    });
  });

  group('wrong types in other reads', () {
    const r = JsonReader({'name': 'Rex', 'tag': null}, schema: 'Pet');

    test('requiredNullable and patch report the property pointer', () {
      final nullable = failure(
        () => r.requiredNullable('name', JsonReader.asInt),
      );
      expect(nullable.pointer, '/name');
      expect(nullable.message, 'expected an integer, got a string');
      expect(nullable.schema, 'Pet');
      final patch = failure(() => r.patch('name', JsonReader.asInt));
      expect(patch.pointer, '/name');
      expect(patch.message, 'expected an integer, got a string');
      expect(patch.schema, 'Pet');
    });
  });

  group('nested paths', () {
    test('array index and nested schema are in the path', () {
      final json =
          jsonDecode('{"tags": [{"name": "a"}, {"name": 3}]}')
              as Map<String, Object?>;
      final r = JsonReader(json, schema: 'Pet');
      final e = failure(
        () => r.required(
          'tags',
          JsonReader.listOf(JsonReader.objectOf(Tag.fromJson)),
        ),
      );
      expect(e.pointer, '/tags/1/name');
      expect(e.path, ['tags', 1, 'name']);
      expect(e.schema, 'Tag');
      expect(e.field, 'name');
    });

    test('map keys are escaped in the pointer', () {
      const r = JsonReader({
        'labels': {'a/b~c': 1},
      }, schema: 'Pet');
      final e = failure(
        () => r.required('labels', JsonReader.mapOf(JsonReader.asString)),
      );
      expect(e.pointer, '/labels/a~1b~0c');
      expect(e.field, 'a/b~c');
    });

    test('valid nested values decode in JSON order', () {
      const r = JsonReader({
        'tags': [
          {'name': 'a'},
          {'name': 'b'},
        ],
        'labels': {'z': 'last', 'a': null},
      }, schema: 'Pet');
      final tags = r.required(
        'tags',
        JsonReader.listOf(JsonReader.objectOf(Tag.fromJson)),
      );
      expect(tags.map((t) => t.name), ['a', 'b']);
      final labels = r.required(
        'labels',
        JsonReader.mapOf(JsonReader.nullable(JsonReader.asString)),
      );
      expect(labels.keys, ['z', 'a']);
      expect(labels['a'], isNull);
    });

    test('a FormatException from a converter becomes a decode error', () {
      const r = JsonReader({
        'when': ['2024-01-01', 'soon'],
      }, schema: 'Event');
      final e = failure(
        () => r.required(
          'when',
          JsonReader.listOf((v) => DateTime.parse(v! as String)),
        ),
      );
      expect(e.pointer, '/when/1');
      expect(e.schema, 'Event');
      expect(e.expected, 'a value its decoder accepts');
    });
  });

  group('primitive decoders', () {
    test('valid values', () {
      expect(JsonReader.asInt(3), 3);
      expect(JsonReader.asDouble(1.5), 1.5);
      expect(JsonReader.asNumber(1.5), 1.5);
      expect(JsonReader.asBool(false), isFalse);
      expect(JsonReader.asString(''), '');
      expect(
        JsonReader.asDateTime('2024-02-03T04:05:06Z'),
        DateTime.utc(2024, 2, 3, 4, 5, 6),
      );
      expect(
        JsonReader.asDateTime('2024-02-03t04:05:06.5+02:00'),
        DateTime.utc(2024, 2, 3, 2, 5, 6, 500),
      );
      expect(
        JsonReader.asDateTime('2024-02-29T23:59:59.999999-00:30'),
        DateTime.utc(2024, 3, 1, 0, 29, 59, 999, 999),
      );
      expect(JsonReader.asValue({'a': 1}).asObject, {'a': 1});
    });

    test('the only widening is an integer where a number is expected', () {
      expect(JsonReader.asDouble(1), 1.0);
      expect(JsonReader.asDouble(1), isA<double>());
      expect(JsonReader.asNumber(1), 1);
      // JavaScript has one number type: 1.0 is the int 1 there.
      if (!TestPlatform.isWeb) {
        expect(failure(() => JsonReader.asInt(1.0)).actual, 'a number');
      }
      expect(failure(() => JsonReader.asInt('1')).actual, 'a string');
      expect(failure(() => JsonReader.asString(1)).actual, 'a number');
      expect(failure(() => JsonReader.asBool('true')).actual, 'a string');
      expect(failure(() => JsonReader.asBool(0)).actual, 'a number');
      if (!TestPlatform.isWeb) {
        // On the VM jsonDecode turns a 30-digit integer into a double; in
        // JavaScript every whole number is an int.
        final huge = jsonDecode('123456789012345678901234567890');
        expect(failure(() => JsonReader.asInt(huge)).expected, 'an integer');
      }
    });

    test('non-finite numbers are rejected', () {
      final infinity = jsonDecode('1e400');
      expect(
        failure(() => JsonReader.asNumber(infinity)).message,
        'expected a finite number, got a number out of the double range',
      );
      expect(
        failure(() => JsonReader.asDouble(infinity)).expected,
        'a finite number',
      );
    });

    test('date-times must be RFC 3339 with an offset', () {
      for (final text in [
        'yesterday',
        '2024-02-03',
        '2024-02-03T04:05:06',
        '2024-02-03 04:05:06Z',
        '2024-13-03T04:05:06Z',
        '2024-02-30T04:05:06Z',
        '2023-02-29T04:05:06Z',
        '2024-02-03T24:05:06Z',
        '2024-02-03T04:05:60Z',
        '2024-02-03T04:05:06+24:00',
      ]) {
        final e = failure(() => JsonReader.asDateTime(text));
        expect(e.expected, 'an RFC 3339 date-time string', reason: text);
        expect(e.hint, JsonReader.dateTimeHint, reason: text);
      }
    });

    test('a date-time without an offset says so and hints at the fix', () {
      const r = JsonReader({'at': '2024-02-03T04:05:06'}, schema: 'Event');
      final e = failure(() => r.required('at', JsonReader.asDateTime));
      expect(e.actual, 'a date-time without an offset');
      expect(
        failure(() => JsonReader.asDateTime('2024-02-03 04:05')).actual,
        'a date-time without an offset',
      );
      expect(
        failure(() => JsonReader.asDateTime('yesterday')).actual,
        'a string in another format',
      );
      expect(
        e.toString(),
        'JsonDecodeException: expected an RFC 3339 date-time string, '
        'got a date-time without an offset at /at in Event. '
        'If the server sends this format on purpose, map it to your own type '
        'with a converter (types.formats in the config, R6.8) or override '
        "the property's format",
      );
      expect(
        JsonDecodeException(expected: 'a', actual: 'b').hint,
        isNull,
      );
    });

    test('containers and other values report their JSON type', () {
      expect(failure(() => JsonReader.asList({})).actual, 'an object');
      expect(failure(() => JsonReader.asObject('x')).actual, 'a string');
      expect(failure(() => JsonReader.asObject(null)).actual, 'null');
      expect(
        failure(() => JsonReader.asString(Object())).actual,
        'a non-JSON value',
      );
    });
  });

  group('asDate', () {
    test('reads a full-date', () {
      expect(JsonReader.asDate('2024-02-03'), Date(2024, 2, 3));
      expect(JsonReader.asDate('2024-02-29'), Date(2024, 2, 29));
    });

    test('a date-time is rejected with the hint', () {
      for (final text in ['2024-02-03T04:05:06Z', '2024-02-03T04:05:06']) {
        final e = failure(() => JsonReader.asDate(text));
        expect(e.expected, 'an RFC 3339 full-date string', reason: text);
        expect(e.actual, contains('date-time'), reason: text);
        expect(e.hint, JsonReader.dateHint, reason: text);
      }
    });

    test('other strings are rejected with the hint', () {
      for (final text in ['2024-02-30', '2023-02-29', '2024-2-3', 'today']) {
        final e = failure(() => JsonReader.asDate(text));
        expect(e.actual, 'a string in another format', reason: text);
        expect(e.hint, JsonReader.dateHint, reason: text);
      }
    });

    test('a non-string is a type mismatch without a hint', () {
      for (final value in [42, null]) {
        final e = failure(() => JsonReader.asDate(value));
        expect(e.expected, 'a string');
        expect(e.hint, isNull);
      }
    });

    test('works with the combinators and properties', () {
      expect(JsonReader.nullable(JsonReader.asDate)(null), isNull);
      expect(
        JsonReader.nullable(JsonReader.asDate)('2024-02-03'),
        Date(2024, 2, 3),
      );
      expect(
        JsonReader.listOf(JsonReader.asDate)(['2024-02-03']),
        [Date(2024, 2, 3)],
      );
      const r = JsonReader({'on': '2024-02-30'}, schema: 'Event');
      final e = failure(() => r.required('on', JsonReader.asDate));
      expect(e.path, ['on']);
    });
  });

  group('checkDepth', () {
    Object? nested(int depth) {
      Object? value = 1;
      for (var i = 0; i < depth; i++) {
        value = i.isEven ? [value] : {'k': value};
      }
      return value;
    }

    test('accepts maxDepth levels and scalars', () {
      JsonReader.checkDepth(nested(JsonReader.maxDepth));
      JsonReader.checkDepth('scalar');
      JsonReader.checkDepth(jsonDecode('{"a": [1, {"b": []}], "c": {}}'));
    });

    test('rejects one level more without overflowing the stack', () {
      final e = failure(
        () => JsonReader.checkDepth(nested(JsonReader.maxDepth + 1)),
      );
      expect(e.expected, 'arrays and objects nested at most 1000 deep');
      expect(e.path, hasLength(JsonReader.maxDepth));
      expect(e.pointer, startsWith('/0/k/0/k/'));
      // Built without a parser, which would overflow the stack in a browser.
      final deep = nested(200000);
      expect(failure(() => JsonReader.checkDepth(deep)).path, hasLength(1000));
      if (!TestPlatform.isWeb) {
        final parsed = jsonDecode('[' * 200000 + ']' * 200000);
        expect(
          failure(() => JsonReader.checkDepth(parsed)).path,
          hasLength(1000),
        );
      }
    });
  });

  group('constants, additional properties and bytes', () {
    test('a constant must hold its one value', () {
      const r = JsonReader({'kind': 'cat', 'n': 1}, schema: 'Cat');
      r.constant('kind', 'cat');
      r.constant('n', 1.0);
      final wrong = failure(() => r.constant('kind', 'dog'));
      expect(wrong.pointer, '/kind');
      expect(wrong.expected, 'the constant "dog"');
      expect(wrong.actual, 'another value');
      expect(wrong.schema, 'Cat');
      expect(
        failure(() => r.constant('n', 'one')).actual,
        'a number',
      );
      expect(failure(() => r.constant('gone', 'x')).actual, 'no value');
    });

    test('an optional constant may be absent or null', () {
      const r = JsonReader({'kind': null}, schema: 'Cat');
      r.constant('kind', 'cat', required: false);
      r.constant('gone', 'cat', required: false);
      expect(
        failure(() => r.constant('kind', 'cat')).actual,
        'null',
      );
    });

    test('additional properties are the keys the schema does not list', () {
      const r = JsonReader({'id': 1, 'b': 2, 'a': 3}, schema: 'Counts');
      final rest = r.additional({'id'}, JsonReader.asInt);
      expect(rest, {'b': 2, 'a': 3});
      expect(rest.keys, ['b', 'a']);
      final wrong = failure(
        () => const JsonReader({
          'x': 'no',
        }, schema: 'Counts').additional(const {}, JsonReader.asInt),
      );
      expect(wrong.pointer, '/x');
      expect(wrong.schema, 'Counts');
    });

    test('bytes are base64, standard or URL-safe, padded or not', () {
      expect(JsonReader.asBytes('AQID'), [1, 2, 3]);
      expect(JsonReader.asBytes('-_8'), [251, 255]);
      expect(JsonReader.asBytes('+/8='), [251, 255]);
      expect(
        failure(() => JsonReader.asBytes('a')).expected,
        'a base64 string',
      );
      expect(failure(() => JsonReader.asBytes(1)).actual, 'a number');
    });
  });

  group('unions and patches of any JSON', () {
    test('attempt returns null when the JSON does not match', () {
      expect(JsonReader.attempt(() => JsonReader.asInt(1)), 1);
      expect(JsonReader.attempt(() => JsonReader.asInt('1')), isNull);
      expect(JsonReader.attempt(() => Date.parse('2024-02-30')), isNull);
      expect(
        () => JsonReader.attempt<int>(() => throw StateError('bug')),
        throwsStateError,
      );
    });

    test('patchValue tells absent, null and a value apart', () {
      const r = JsonReader({'a': null, 'b': 1}, schema: 'Body');
      expect(r.patchValue('gone'), isNull);
      expect(r.patchValue('a'), const Patch<JsonValue>.nullValue());
      expect(r.patchValue('b'), const Patch.value(JsonValue(1)));
    });
  });

  group('JsonValue', () {
    test('wraps any JSON value and encodes as is', () {
      const value = JsonValue({
        'a': [1, 'x'],
      });
      expect(jsonEncode(value), '{"a":[1,"x"]}');
      expect(JsonValue.fromJson(null).isNull, isTrue);
      expect(value.raw, {
        'a': [1, 'x'],
      });
      expect(value.asObject?['a'], [1, 'x']);
      expect(value.asList, isNull);
      expect(const JsonValue('s').asString, 's');
      expect(const JsonValue(2).asNumber, 2);
      expect(const JsonValue(true).asBool, isTrue);
      expect(const JsonValue(true).toJson(), isTrue);
    });

    test('lookups chain and never throw', () {
      const value = JsonValue({
        'a': [1, 'x'],
      });
      expect(value['a'][1].asString, 'x');
      expect(value['a'][0].asNumber, 1);
      expect(value['a'][2].isNull, isTrue);
      expect(value['a'][-1].isNull, isTrue);
      expect(value['b']['c'].isNull, isTrue);
      expect(value[0].isNull, isTrue);
      expect(value['a']['x'].isNull, isTrue);
      expect(value['a'][0].asString, isNull);
    });
  });
}
