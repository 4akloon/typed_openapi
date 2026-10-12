import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  // The values of the OAS "Style Examples" table.
  const empty = '';
  const string = 'blue';
  const array = ['blue', 'black', 'brown'];
  const object = {'R': 100, 'G': 200, 'B': 150};

  group('path styles (OAS style examples)', () {
    String path(PathStyle style, bool explode, Object? value) =>
        PathParameter('color', value, style: style, explode: explode).encode();

    test('simple', () {
      expect(path(.simple, false, string), 'blue');
      expect(path(.simple, false, array), 'blue,black,brown');
      expect(path(.simple, true, array), 'blue,black,brown');
      expect(path(.simple, false, object), 'R,100,G,200,B,150');
      expect(path(.simple, true, object), 'R=100,G=200,B=150');
      expect(const PathParameter('id', 42).encode(), '42');
    });

    test('label', () {
      expect(path(.label, false, string), '.blue');
      expect(path(.label, false, array), '.blue,black,brown');
      expect(path(.label, true, array), '.blue.black.brown');
      expect(path(.label, false, object), '.R,100,G,200,B,150');
      expect(path(.label, true, object), '.R=100.G=200.B=150');
    });

    test('matrix', () {
      expect(path(.matrix, false, empty), ';color');
      expect(path(.matrix, true, empty), ';color');
      expect(path(.matrix, false, string), ';color=blue');
      expect(path(.matrix, false, array), ';color=blue,black,brown');
      expect(path(.matrix, true, array), ';color=blue;color=black;color=brown');
      expect(path(.matrix, false, object), ';color=R,100,G,200,B,150');
      expect(path(.matrix, true, object), ';R=100;G=200;B=150');
    });

    test('values cannot add path segments or queries', () {
      expect(const PathParameter('id', 'a/b?c#d').encode(), 'a%2Fb%3Fc%23d');
      expect(const PathParameter('id', 'über ok').encode(), '%C3%BCber%20ok');
      expect(const PathParameter('id', "!*'()").encode(), '%21%2A%27%28%29');
      expect(const PathParameter('id', '-._~').encode(), '-._~');
    });

    test('a dot segment would change the request path', () {
      for (final style in PathStyle.values) {
        for (final dots in ['.', '..']) {
          for (final value in [
            dots,
            [dots],
            ['ok', dots],
            {'k': dots},
          ]) {
            expect(
              () => path(style, false, value),
              throwsA(
                isA<ArgumentError>().having(
                  (e) => e.message,
                  'message',
                  contains('cannot be a dot segment'),
                ),
              ),
              reason: '$style $value',
            );
          }
        }
      }
      expect(path(.simple, false, 'a.b'), 'a.b');
    });

    test('an empty or all-dot expansion would drop or climb a segment', () {
      // The expansions of the OAS examples for an empty value: '' and '.'
      // are not path segments (Dio collapses `//` and drops `.`).
      final cases = <String, PathParameter>{
        'simple empty': const PathParameter('id', ''),
        'simple [empty]': const PathParameter('id', ['']),
        'simple no items': const PathParameter('id', <String>[]),
        'simple null': const PathParameter('id', null),
        'simple empty map': const PathParameter('id', <String, Object?>{}),
        'label empty': const PathParameter('id', '', style: .label),
        'label [empty]': const PathParameter('id', [''], style: .label),
        'label [empty, empty] exploded': const PathParameter(
          'id',
          ['', ''],
          style: .label,
          explode: true,
        ),
        'label [empty, empty, empty] exploded': const PathParameter(
          'id',
          ['', '', ''],
          style: .label,
          explode: true,
        ),
        'label no items': const PathParameter('id', <String>[], style: .label),
        'label null': const PathParameter('id', null, style: .label),
        'matrix null': const PathParameter('id', null, style: .matrix),
        'matrix no items': const PathParameter(
          'id',
          <String>[],
          style: .matrix,
        ),
        'simple three dots': const PathParameter('id', '...'),
      };
      for (final MapEntry(key: label, value: parameter) in cases.entries) {
        expect(
          parameter.encode,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('would change the request path'),
                anyOf(
                  contains('cannot be empty'),
                  contains('cannot be only dots'),
                ),
              ),
            ),
          ),
          reason: label,
        );
      }
    });

    test('valid neighbours of the rejected values', () {
      expect(const PathParameter('id', '.a').encode(), '.a');
      expect(const PathParameter('id', 'a.').encode(), 'a.');
      expect(const PathParameter('id', 'a..b').encode(), 'a..b');
      expect(const PathParameter('id', ' ').encode(), '%20');
      expect(const PathParameter('id', ['', '']).encode(), ',');
      expect(
        const PathParameter('id', ['a', 'b'], style: .label).encode(),
        '.a,b',
      );
      expect(
        const PathParameter(
          'id',
          ['a', 'b'],
          style: .label,
          explode: true,
        ).encode(),
        '.a.b',
      );
      expect(
        const PathParameter('id', ['', ''], style: .label).encode(),
        '.,',
      );
      expect(const PathParameter('id', '', style: .matrix).encode(), ';id');
      expect(
        const PathParameter(
          'id',
          ['', ''],
          style: .matrix,
          explode: true,
        ).encode(),
        ';id;id',
      );
      expect(const PathParameter('id', 0).encode(), '0');
    });

    test('matrix keeps an empty item or value without "="', () {
      expect(path(.matrix, true, const ['', 'x']), ';color;color=x');
      expect(path(.matrix, true, const {'R': '', 'G': 1}), ';R;G=1');
      expect(path(.matrix, false, const ['', 'x']), ';color=,x');
      expect(path(.simple, true, const {'R': '', 'G': 1}), 'R=,G=1');
    });
  });

  group('query styles (OAS style examples)', () {
    String query(
      Object? value, {
      QueryStyle style = .form,
      bool? explode,
      bool allowReserved = false,
    }) => QueryParameter(
      'color',
      value,
      style: style,
      explode: explode,
      allowReserved: allowReserved,
    ).encode();

    test('form', () {
      expect(query(empty), 'color=');
      expect(query(string), 'color=blue');
      expect(query(array), 'color=blue&color=black&color=brown');
      expect(query(array, explode: false), 'color=blue,black,brown');
      expect(query(object), 'R=100&G=200&B=150');
      expect(query(object, explode: false), 'color=R,100,G,200,B,150');
    });

    test('spaceDelimited and pipeDelimited default to no explode', () {
      expect(
        query(array, style: .spaceDelimited),
        'color=blue%20black%20brown',
      );
      expect(
        query(object, style: .spaceDelimited),
        'color=R%20100%20G%20200%20B%20150',
      );
      expect(query(array, style: .pipeDelimited), 'color=blue%7Cblack%7Cbrown');
      expect(
        query(array, style: .pipeDelimited, explode: true),
        'color=blue&color=black&color=brown',
      );
      expect(
        const QueryParameter('a', 1, style: .pipeDelimited).explode,
        isFalse,
      );
      expect(const QueryParameter('a', 1).explode, isTrue);
    });

    test('deepObject', () {
      expect(
        query(object, style: .deepObject),
        'color%5BR%5D=100&color%5BG%5D=200&color%5BB%5D=150',
      );
      expect(query(null, style: .deepObject), '');
      expect(
        () => query(array, style: .deepObject),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('scalars, nulls and order', () {
      expect(query(1.5), 'color=1.5');
      expect(query(true), 'color=true');
      expect(query(null), '');
      expect(query(const <Object?>[]), '');
      expect(query(const ['a', null, 'b']), 'color=a&color=b');
      expect(query(const {'z': 1, 'a': null, 'b': 2}), 'z=1&b=2');
    });

    test('empty list items and empty object values', () {
      expect(query(const ['', 'a']), 'color=&color=a');
      expect(query(const ['', 'a'], explode: false), 'color=,a');
      expect(query(const {'R': '', 'G': 1}), 'R=&G=1');
    });

    test('names are percent-encoded as UTF-8', () {
      expect(
        const QueryParameter('ключ', 1).encode(),
        '%D0%BA%D0%BB%D1%8E%D1%87=1',
      );
      expect(
        const QueryParameter('ü', 'ü').encode(),
        '%C3%BC=%C3%BC',
      );
    });

    test('names and values are percent-encoded', () {
      expect(
        const QueryParameter('a b[]', 'x&y=z+w#v').encode(),
        'a%20b%5B%5D=x%26y%3Dz%2Bw%23v',
      );
    });

    test('allowReserved keeps reserved characters that are safe', () {
      expect(
        query(r"a/b?c:d@e!f$g'h(i)j*k,l;m", allowReserved: true),
        r"color=a/b?c:d@e!f$g'h(i)j*k,l;m",
      );
      expect(
        query('x&y=z+w#v[0] %41%zz', allowReserved: true),
        'color=x%26y%3Dz%2Bw%23v%5B0%5D%20%41%25zz',
      );
      expect(query('a/b'), 'color=a%2Fb');
    });
  });

  group('header and cookie', () {
    test('headers use simple style without percent-encoding', () {
      expect(
        const HeaderParameter('X-Ids', array).encode(),
        'blue,black,brown',
      );
      expect(
        const HeaderParameter('X-Color', object, explode: true).encode(),
        'R=100,G=200,B=150',
      );
      expect(
        const HeaderParameter('X-Text', 'a b/c,"d"').encode(),
        'a b/c,"d"',
      );
      expect(const HeaderParameter('X-None', null).encode(), isNull);
    });

    test('a header value cannot break the header line', () {
      expect(
        const HeaderParameter('X-Text', 'a\r\nInjected: 1').encode(),
        'a%0D%0AInjected: 1',
      );
      expect(const HeaderParameter('X-Text', 'ü').encode(), '%C3%BC');
    });

    test('cookies are name=value pairs joined by "; "', () {
      expect(const CookieParameter('id', 'a b;c').encode(), 'id=a%20b%3Bc');
      expect(
        const CookieParameter('ids', array).encode(),
        'ids=blue; ids=black; ids=brown',
      );
      expect(
        const CookieParameter('ids', array, explode: false).encode(),
        'ids=blue,black,brown',
      );
      expect(
        const CookieParameter('o', object).encode(),
        'R=100; G=200; B=150',
      );
      expect(const CookieParameter('id', null).encode(), isNull);
    });
  });

  test('values that are not JSON scalars are a programming error', () {
    expect(
      () => const PathParameter('id', [
        ['nested'],
      ]).encode(),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => const QueryParameter('q', [
        {'a': 1},
      ]).encode(),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'nested objects/arrays are not supported in a form parameter',
        ),
      ),
    );
    expect(
      () => const PathParameter('p', {
        'a': [1],
      }, style: .label).encode(),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('in a label parameter'),
        ),
      ),
    );
    expect(
      () => QueryParameter('t', DateTime(2024)).encode(),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => const QueryParameter('n', double.infinity).encode(),
      throwsA(isA<ArgumentError>()),
    );
  });
}
