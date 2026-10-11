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

      test('a chain of aliases that nests too deep is reported', () {
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse(chain(1500), 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.pointer!.tokens, hasLength(NestingScanner.maxDepth));
        expect(d.pointer!.tokens.take(3), ['components', 'schemas', 'a997']);
        expect(d.span, isNotNull);
      }, timeout: limit);

      test('aliases whose text is shallow but expand deep are reported, '
          'not a stack overflow', () {
        final bag = DiagnosticBag();
        final text = chain(80, levelsEach: 60);
        expect(const NestingScanner().findTooDeep(text), isNull);
        expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
        expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
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
