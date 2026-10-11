import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';

import '../helpers/temp_dir.dart';

void main() {
  group('SpecLoader.parse', () {
    test('reads JSON with positions for every node', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{\n  "openapi": "3.0.3",\n  "paths": {\n    "/users": {}\n  }\n}',
        'api.json',
      )!;
      expect(bag.all, isEmpty);
      expect(doc.root['openapi'], '3.0.3');
      expect(doc.hasPositions, isTrue);
      final span = doc.spanOf(JsonPointer.root.child('paths').child('/users'))!;
      expect(span.start.line, 3);
      expect(span.start.column, 14);
    });

    test('reads YAML and turns non-string keys into strings', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.1.0\nresponses:\n  200:\n    description: ok\n',
        'api.yaml',
      )!;
      expect(bag.all, isEmpty);
      expect(doc.root['responses'], {
        '200': {'description': 'ok'},
      });
    });

    test('reports a syntax error with its position', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{\n  "openapi": "3.0.3",\n',
        'api.json',
      );
      expect(doc, isNull);
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.parseError);
      expect(d.severity, Severity.error);
      expect(d.span, isNotNull);
    });

    test('a duplicate key in JSON is a warning; the last value wins', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{"openapi": "3.0.3", "info": {"title": "a"}, "info": {"title": "b"}}',
        'api.json',
      )!;
      expect(doc.root['info'], {'title': 'b'});
      expect(doc.hasPositions, isFalse);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.positionsUnavailable,
      ]);
      expect(bag.hasErrors, isFalse);
    });

    test('a duplicate key in YAML is an error', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\npaths: {}\npaths: {}\n',
        'a.yaml',
      );
      expect(doc, isNull);
      expect(bag.all.single.code, DiagnosticCode.duplicateKey);
      expect(bag.all.single.severity, Severity.error);
    });

    test('a root that is not an object is an error', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.rootNotObject);
    });

    test('nesting deeper than the limit is an error, not a crash', () {
      final bag = DiagnosticBag();
      final text = '{"a": ${'[' * 20000}${']' * 20000}}';
      expect(SpecLoader(bag).parse(text, 'api.json'), isNull);
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.nestingTooDeep);
      expect(d.column, 7 + NestingScanner.maxDepth - 1);
    });

    test('YAML nested deeper than the limit is an error too', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- ' * 20000, 'api.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
    });

    group('aliases', () {
      const limit = Timeout(Duration(seconds: 5));

      String chain(int anchors, {int levelsEach = 1}) {
        final text = StringBuffer(
          'openapi: 3.1.0\ncomponents:\n  schemas:\n'
          '    a0: &a0 {type: string}\n',
        );
        for (var i = 1; i <= anchors; i++) {
          text.writeln(
            '    a$i: &a$i ${'{items: ' * levelsEach}*a${i - 1}'
            '${'}' * levelsEach}',
          );
        }
        return '$text';
      }

      /// A document whose text nests [levels] deep, with an alias of it
      /// inside a text that is [levels] deep again. Comments pad the text so
      /// that the expansion stays within the budget.
      String deepAlias(int levels) =>
          'openapi: 3.1.0\n# ${'p' * 100000}\n'
          'x-deep: &deep ${'[' * levels}x${']' * levels}\n'
          'x-use: ${'[' * levels}*deep${']' * levels}\n';

      test('aliases whose text is shallow but expand deep are reported, '
          'not a stack overflow', () {
        final bag = DiagnosticBag();
        final text = deepAlias(600);
        expect(const NestingScanner().findTooDeep(text), isNull);
        expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.message, contains('alias'));
        expect(d.pointer!.tokens, hasLength(NestingScanner.maxDepth + 1));
        expect(d.pointer!.tokens.take(2), ['x-use', '0']);
        expect(d.span, isNotNull);
      }, timeout: limit);

      test('a chain of aliases is bounded by cost long before it is deep '
          'enough to overflow', () {
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse(chain(1500), 'api.yaml'), isNull);
        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
      }, timeout: limit);

      test('an alias bomb is reported once and not expanded', () {
        final text = StringBuffer(
          'openapi: 3.1.0\nx-bomb:\n  l0: &l0 [x, x, x, x, x, x, x, x, x]\n',
        );
        for (var i = 1; i <= 9; i++) {
          text.writeln(
            '  l$i: &l$i [${List.filled(9, '*l${i - 1}').join(', ')}]',
          );
        }
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
        expect(d.severity, Severity.error);
        expect(d.pointer!.value, startsWith('#/x-bomb/l'));
        expect(d.span, isNotNull);
      }, timeout: limit);

      test('a wide and deep alias chain is bounded by what it costs, '
          'not by node count', () {
        // 900 nested anchors, then thousands of aliases of the deepest one:
        // every expanded node is hundreds of levels down and stores a
        // pointer that long, so the node count alone is a poor budget.
        final text = StringBuffer(chain(900));
        for (var i = 0; text.length < 200 * 1024; i++) {
          text.writeln('    u$i: *a900');
        }
        final bag = DiagnosticBag();
        final watch = Stopwatch()..start();
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNull);
        watch.stop();
        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      }, timeout: limit);

      test('a document exactly as deep as the limit is accepted', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-deep: '
              '${'[' * NestingScanner.maxDepth}${']' * NestingScanner.maxDepth}\n',
          'api.yaml',
        );
        expect(doc, isNotNull);
        expect(bag.all, isEmpty);
      }, timeout: limit);

      test('one level past the limit is the scanner\'s nesting-too-deep', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-deep: '
              '${'[' * (NestingScanner.maxDepth + 1)}'
              '${']' * (NestingScanner.maxDepth + 1)}\n',
          'api.yaml',
        );
        expect(doc, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.message, isNot(contains('alias')));
      }, timeout: limit);

      test('aliases that stay small are expanded as written', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse('''
openapi: 3.1.0
x-base: &base {a: 1, b: [x, y]}
x-one: *base
x-two: *base
''', 'api.yaml')!;
        expect(doc.root['x-two'], {
          'a': 1,
          'b': ['x', 'y'],
        });
        expect(doc.spanOf(JsonPointer.parse('#/x-two/b/1')), isNotNull);
        expect(bag.all, isEmpty);
      }, timeout: limit);
    });

    group('alias keys', () {
      const limit = Timeout(Duration(seconds: 5));

      String bomb(String key) {
        final text = StringBuffer(
          'openapi: 3.1.0\nx-bomb:\n  l0: &l0 [x, x, x, x, x, x, x, x, x]\n',
        );
        for (var i = 1; i <= 7; i++) {
          text.writeln(
            '  l$i: &l$i [${List.filled(9, '*l${i - 1}').join(', ')}]',
          );
        }
        text.writeln('x-key:');
        text.writeln(key);
        return '$text';
      }

      for (final (name, key) in [
        ('after a ? marker', '  ? *l7\n  : v'),
        ('inside a ? key sequence', '  ? [*l7]\n  : v'),
        ('inside a ? key block sequence', '  ? - *l7\n  : v'),
        ('before a colon', '  *l7 : v'),
        ('in a flow mapping', '  {*l7 : v}'),
        ('as an entry of a flow mapping', '  {a: 1, *l7 : v}'),
        ('as a bare entry of a flow mapping', '  {*l7, a: 1}'),
      ]) {
        test('an alias $name is rejected fast, without expanding', () {
          final bag = DiagnosticBag();
          final watch = Stopwatch()..start();
          expect(SpecLoader(bag).parse(bomb(key), 'api.yaml'), isNull);
          watch.stop();
          final d = bag.all.single;
          expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
          expect(d.message, contains('key'));
          expect(d.span, isNotNull);
          expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
        }, timeout: limit);
      }

      test('a merge key and aliases in values are accepted', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          '''
openapi: 3.1.0
x-base: &base {a: 1}
x-ref: &ref [1, 2]
x-merge:
  <<: *base
  b: 2
x-value: *ref
x-flow: {k: *ref, j: [*ref, *base]}
x-seq:
  - *ref
  - *base
''',
          'api.yaml',
        );
        expect(bag.all, isEmpty);
        expect(doc, isNotNull);
        expect(doc!.root['x-value'], [1, 2]);
      }, timeout: limit);

      test('a * inside quotes or plain text is not an alias', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          '''
openapi: 3.1.0
x-a: {"*k": 1, '*j': 2, p*q: 3}
"*l" : 4
'*m': 5
x-b: a * b
''',
          'api.yaml',
        );
        expect(bag.all.where((d) => d.severity == Severity.error), isEmpty);
        expect(doc, isNotNull);
      }, timeout: limit);
    });

    test('YAML keys 1 and "1" are one JSON key: a warning, last wins', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\nresponses:\n  200: {description: a}\n'
            '  "200": {description: b}\n',
        'api.yaml',
      )!;
      expect(doc.root['responses'], {
        '200': {'description': 'b'},
      });
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.duplicateKey);
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/responses/200');
      expect(d.line, 4);
    });

    test('JSON with a duplicate key and a syntax error reports both', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{"openapi": "3.0.3", "a": 1, "a": 2,\n',
        'api.json',
      );
      expect(doc, isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.parseError,
      ]);
      expect(bag.all.last.severity, Severity.error);
      expect(bag.all.last.line, 2);
    });

    test('a JSON root that is not an object is reported before positions', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('[{"a": 1, "a": 2}]', 'api.json'), isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.rootNotObject,
      ]);
    });
  });

  group('SpecLoader.load', () {
    test('reports a missing file', () {
      final bag = DiagnosticBag();
      expect(
        SpecLoader(bag).load('/nope/api.json', displayPath: 'api.json'),
        isNull,
      );
      expect(bag.all.single.code, DiagnosticCode.inputNotFound);
      expect(bag.all.single.file, 'api.json');
    });

    test('reports a file that is not UTF-8', () {
      final dir = TempDir();
      final path = p.join(dir.path, 'bad.json');
      File(path).writeAsBytesSync([0xFF, 0xFE, 0x41]);
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(path), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
    });
    test('reports a directory given as the spec', () {
      final dir = TempDir();
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(dir.path, displayPath: 'specs'), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
      expect(bag.all.single.message, contains('is a directory'));
    });

    test('reads a file from disk', () {
      final path = TempDir().write('api.yaml', 'openapi: 3.0.3\n');
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(path)!.root, {'openapi': '3.0.3'});
    });
  });
}
