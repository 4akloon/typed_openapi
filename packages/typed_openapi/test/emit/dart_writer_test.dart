import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/dart_code.dart';
import 'package:typed_openapi/src/emit/dart_writer.dart';
import 'package:typed_openapi/src/emit/imports.dart';

void main() {
  const code = DartCode();

  group('DartCode', () {
    test('escapes every character a string literal cannot hold', () {
      expect(code.string("it's"), r"'it\'s'");
      expect(code.string(r'$x ${y}'), r"'\$x \${y}'");
      expect(code.string(r'a\b'), r"'a\\b'");
      expect(code.string('a\nb\r\tc'), r"'a\nb\r\tc'");
      expect(
        code.string('\x00\x1f\x7f\x85\u2028\u2029'),
        r"'\u{0}\u{1f}\u{7f}\u{85}\u{2028}\u{2029}'",
      );
      expect(code.string('\ud800'), r"'\u{d800}'");
      expect(code.string("ім'я 🐱"), r"'ім\'я 🐱'");
    });

    test('writes bidirectional controls as escapes (trojan source)', () {
      expect(
        code.string('a\u202eb\u2066c\u2069d\u202a'),
        r"'a\u{202e}b\u{2066}c\u{2069}d\u{202a}'",
      );
      // Neighbours of the ranges stay as they are.
      expect(code.string('\u2029\u202f\u2065\u206a'), contains('\u202f'));
    });

    test('refuses a number that has no literal', () {
      expect(() => code.literal(double.nan), throwsStateError);
      expect(() => code.literal(double.infinity), throwsStateError);
      expect(() => code.literal(double.negativeInfinity), throwsStateError);
      expect(code.literal(1e21), '1e+21');
    });

    test('writes JSON scalars as constants', () {
      expect(code.literal('a'), "'a'");
      expect(code.literal(-3), '-3');
      expect(code.literal(2.0), '2.0');
      expect(code.literal(0.25), '0.25');
      expect(code.literal(true), 'true');
      expect(code.literal(null), 'null');
    });

    test('interpolates names with a dollar in braces', () {
      expect(code.interpolate('name'), r'$name');
      expect(code.interpolate(r'$2fa'), r'${$2fa}');
    });

    test('escapes doc text outside code spans and fences', () {
      expect(code.docLines(r'A <b> [c] d\e `x<y>` */', 80), [
        r'A \<b\> \[c\] d\\e `x<y>` */',
      ]);
      expect(code.docLines('odd ` <b>', 80), [r'odd ` \<b\>']);
      expect(code.docLines('\n\nText\r\n\n```\n<raw> [x]\n```\n\n', 80), [
        'Text',
        '',
        '```',
        '<raw> [x]',
        '```',
      ]);
      expect(code.docLines('```\nopen <fence>', 80), [
        '```',
        'open <fence>',
        '```',
      ]);
      expect(code.docLines('a\x01b', 80), ['ab']);
    });

    test('never breaks a code span when it wraps (corpus: ditto)', () {
      expect(code.docLines('Both `{{ thing-json:<json-pointer> }}` work', 24), [
        'Both',
        '`{{ thing-json:<json-pointer> }}`',
        'work',
      ]);
    });

    test('neutralises doc directives', () {
      expect(code.docLines('See {@link Foo} and {@template t}', 80), [
        r'See \{@link Foo} and \{@template t}',
      ]);
      expect(code.docLines('{ not @a directive }', 80), [
        '{ not @a directive }',
      ]);
    });

    test('neutralises doc directives inside a fenced block', () {
      expect(
        code.docLines(
          '```\n{@youtube 560 315 https://x.example/v}\n{@macro m} <raw>\n```',
          80,
        ),
        [
          '```',
          r'\{@youtube 560 315 https://x.example/v}',
          r'\{@macro m} <raw>',
          '```',
        ],
      );
      // An unclosed fence is closed, and its directives are neutralised too.
      expect(code.docLines('```\n{@template t}', 80), [
        '```',
        r'\{@template t}',
        '```',
      ]);
    });

    test('drops bidirectional controls and fixes lone surrogates', () {
      expect(code.docLines('a\u202eb\u2066c\u2069d', 80), ['abcd']);
      expect(code.docLines('a\ud800b\udc00c', 80), ['a\ufffdb\ufffdc']);
      expect(code.docLines('a\u{1F431}b', 80), ['a\u{1F431}b']);
    });

    test('a lone carriage return is a line break', () {
      expect(code.docLines('a\rb\r\nc', 80), ['a', 'b', 'c']);
    });

    test('wrapping leaves no trailing space', () {
      expect(
        code.docLines('aaaaaaaaaaaaaaa   bbbbbbbbbbbbb', 20),
        ['aaaaaaaaaaaaaaa', 'bbbbbbbbbbbbb'],
      );
      for (final line in code.docLines(
        'x  ' * 40 + 'word    ' * 10,
        24,
      )) {
        expect(line, isNot(endsWith(' ')));
      }
    });

    test('a line with inline text after the backticks opens no fence', () {
      expect(code.docLines('```a``` <b> [x]\n<c>', 80), [
        r'```a``` \<b\> \[x\]',
        r'\<c\>',
      ]);
      expect(code.docLines('```dart\n<raw>\n```  \n<c>', 80), [
        '```dart',
        '<raw>',
        '```',
        r'\<c\>',
      ]);
    });

    test('wraps long doc lines at the width, keeping the indent', () {
      expect(
        code.docLines('  one two three four five six seven', 20),
        ['  one two three four', '  five six seven'],
      );
      expect(code.docLines('averyveryverylongwordthatdoesnotfit x', 20), [
        'averyveryverylongwordthatdoesnotfit',
        'x',
      ]);
    });
  });

  group('DartWriter', () {
    test('indents blocks and keeps empty lines empty', () {
      final out = DartWriter(80);
      out.block('class A', () {
        out
          ..line('int a;')
          ..line()
          ..block('void f()', () => out.line('g();'));
      });
      expect(
        out.text,
        'class A {\n'
        '  int a;\n'
        '\n'
        '  void f() {\n'
        '    g();\n'
        '  }\n'
        '}\n',
      );
    });

    test('a line cannot hold a line break', () {
      expect(() => DartWriter(80).line('a\nb'), throwsA(isA<AssertionError>()));
    });

    test('puts a list on one line when it fits, else one item a line', () {
      final out = DartWriter(30)
        ..list('f(', ['a', 'b'], ');')
        ..list('const LongName({', ['required this.a', 'this.b'], '});')
        ..list('g(', [], ');');
      expect(
        out.text,
        'f(a, b);\n'
        'const LongName({\n'
        '  required this.a,\n'
        '  this.b,\n'
        '});\n'
        'g();\n',
      );
    });

    test('breaks a long chain one operand a line', () {
      final out = DartWriter(40)
        ..chain('bool operator ==(Object o) =>', ['o is A'], '&&')
        ..chain('bool operator ==(Object o) =>', [
          'o is A',
          'o.first == first',
        ], '&&');
      expect(
        out.text,
        'bool operator ==(Object o) => o is A;\n'
        'bool operator ==(Object o) =>\n'
        '    o is A &&\n'
        '    o.first == first;\n',
      );
    });

    test('writes doc comments at the indentation', () {
      final out = DartWriter(80);
      out.indented(() => out.doc('Line <one>.\n\nTwo.'));
      out.doc(null);
      expect(out.text, '  /// Line \\<one\\>.\n  ///\n  /// Two.\n');
    });
  });

  test('Imports writes sorted sections and show lists', () {
    final imports = Imports('pet.dart')
      ..fromRuntime('JsonReader')
      ..fromRuntime('Date')
      ..fromRuntime('JsonReader')
      ..show('dart:typed_data', 'Uint8List')
      ..show('dart:convert', 'base64Encode')
      ..show('package:app/money.dart', 'Money')
      ..file('tag.dart')
      ..file('pet.dart')
      ..file('cat.dart');
    final out = DartWriter(100);
    imports.write(out);
    expect(
      out.text,
      "import 'dart:convert' show base64Encode;\n"
      "import 'dart:typed_data' show Uint8List;\n"
      '\n'
      "import 'package:app/money.dart' show Money;\n"
      "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart' "
      'show Date, JsonReader;\n'
      '\n'
      "import 'cat.dart';\n"
      "import 'tag.dart';\n"
      '\n',
    );
    final narrow = DartWriter(40);
    (Imports('a.dart')..fromRuntime('JsonReader')).write(narrow);
    expect(
      narrow.text,
      "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'\n"
      '    show JsonReader;\n'
      '\n',
    );
  });

  test('Imports wraps a long show list at the width', () {
    final imports = Imports('a.dart');
    for (final name in ['AVeryLongNameOne', 'AVeryLongNameTwo', 'Three']) {
      imports.fromRuntime(name);
    }
    final out = DartWriter(40);
    imports.write(out);
    expect(
      out.text,
      "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'\n"
      '    show\n'
      '        AVeryLongNameOne,\n'
      '        AVeryLongNameTwo,\n'
      '        Three;\n'
      '\n',
    );
  });
}
