import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/load/yaml_composer.dart';

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
      expect(doc.hasPositions, isTrue);
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.duplicateKey);
      expect(d.pointer?.value, '#/info');
      expect(bag.hasErrors, isFalse);
    });

    test('a YAML tag outside the JSON Schema ruleset is an error, and the '
        'rest of the document is read', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\nx-when: !!timestamp 2025-07-27T07:17:05Z\n',
        'api.yaml',
      )!;
      expect(doc.root['x-when'], '2025-07-27T07:17:05Z');
      expect(bag.all.single.code, DiagnosticCode.yamlTagUnsupported);
    });

    test('a duplicate key in YAML is an error; the last value is used', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\npaths: {/a: {}}\npaths: {}\n',
        'a.yaml',
      )!;
      expect(doc.root['paths'], <String, Object?>{});
      expect(bag.all.single.code, DiagnosticCode.duplicateKey);
      expect(bag.all.single.severity, Severity.error);
    });

    test('a second YAML document is a parse error, as in package:yaml', () {
      final bag = DiagnosticBag();
      expect(
        SpecLoader(
          bag,
        ).parse('openapi: 3.1.0\n---\nopenapi: 3.0.0\n', 'a.yaml'),
        isNull,
      );
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.parseError);
      expect(d.span, isNotNull);
    });

    group('long flow lines', () {
      const limit = Timeout(Duration(seconds: 30));

      for (final (name, text) in [
        ('quoted closers', 'openapi: 3.1.0\nx-a: ${'["]",' * 199000}'),
        ('quoted closers in a JSON-style object', '{"a": ${'["]",' * 199000}'),
      ]) {
        test('$name are TOA007 at a position', () {
          final bag = DiagnosticBag();
          expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
          final d = bag.all.single;
          expect(d.code, DiagnosticCode.nestingTooDeep);
          expect(d.span, isNotNull);
        }, timeout: limit);
      }

      test('a spec with many short flow collections is read', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-pairs: [${'[1, 2], ' * 40000}0]\n',
          'api.yaml',
        )!;
        expect(bag.all, isEmpty);
        expect((doc.root['x-pairs']! as List<Object?>).length, 40001);
      }, timeout: limit);
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
      expect(d.column, 7 + YamlComposer.maxDepth);
    });

    test('YAML nested deeper than the limit is an error too', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- ' * 20000, 'api.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
    });

    group('aliases', () {
      const limit = Timeout(Duration(seconds: 30));

      /// Anchors a0..a[anchors], each a mapping that holds the previous one
      /// as a block value.
      String chain(int anchors) {
        final text = StringBuffer(
          'openapi: 3.1.0\ncomponents:\n  schemas:\n'
          '    a0: &a0 {type: string}\n',
        );
        for (var i = 1; i <= anchors; i++) {
          text.writeln('    a$i: &a$i\n      items: *a${i - 1}');
        }
        return '$text';
      }

      /// A document whose text nests 600 levels deep (a flow sequence), with
      /// an alias of it under 450 block sequences (the scan counts each `- `
      /// as 2 levels, so that is 900 for it).
      String deepAlias() =>
          'openapi: 3.1.0\n'
          'x-deep: &deep ${'[' * 600}x${']' * 600}\n'
          'x-use:\n  ${'- ' * 450}*deep\n';

      test('aliases whose text is shallow but expand deep are reported, '
          'not a stack overflow', () {
        final bag = DiagnosticBag();
        final text = deepAlias();
        expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.message, contains('alias'));
        expect(d.pointer!.tokens, hasLength(YamlComposer.maxDepth + 1));
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
          text.writeln('  l$i: &l$i');
          for (var n = 0; n < 9; n++) {
            text.writeln('    - *l${i - 1}');
          }
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
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNull);
        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
      }, timeout: limit);

      test('a document exactly as deep as the limit is accepted', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-deep: '
              '${'[' * YamlComposer.maxDepth}${']' * YamlComposer.maxDepth}\n',
          'api.yaml',
        );
        expect(doc, isNotNull);
        expect(bag.all, isEmpty);
      }, timeout: limit);

      test('one level past the limit is the scanner\'s nesting-too-deep', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-deep: '
              '${'[' * (YamlComposer.maxDepth + 1)}'
              '${']' * (YamlComposer.maxDepth + 1)}\n',
          'api.yaml',
        );
        expect(doc, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.message, isNot(contains('alias')));
      }, timeout: limit);

      for (final extension in ['json', 'yaml']) {
        test('a root mapping with 1000 nested [ is accepted in .$extension, '
            '1001 is not', () {
          String doc(int levels) =>
              '{"openapi": "3.1.0", "x": ${'[' * levels}${']' * levels}}';
          final bag = DiagnosticBag();
          expect(
            SpecLoader(bag).parse(doc(YamlComposer.maxDepth), 'a.$extension'),
            isNotNull,
          );
          expect(bag.all, isEmpty);
          expect(
            SpecLoader(
              bag,
            ).parse(doc(YamlComposer.maxDepth + 1), 'a.$extension'),
            isNull,
          );
          expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
        }, timeout: limit);
      }

      test('long keys above an aliased node are charged by the pointer '
          'length they cost, not by depth', () {
        // One 20 000 character key, aliased 20 000 times: every alias
        // stores a pointer that long.
        final key = 'k' * 20000;
        final text = StringBuffer(
          'openapi: 3.1.0\nx-a: &a {$key: 1}\nx-b:\n',
        );
        for (var i = 0; i < 20000; i++) {
          text.writeln('  - *a');
        }
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
        expect(d.message, contains('alias'));
      }, timeout: limit);

      test('long keys above many leaves without any alias are charged too, '
          'and the message does not blame aliases', () {
        final text = StringBuffer(
          'openapi: 3.1.0\nx-a:\n  ${'k' * 20000}: [',
        )..write(List.filled(20000, '1').join(', '));
        text.writeln(']');
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
        expect(d.message, isNot(contains('alias')));
        expect(d.message, contains('pointer'));
      }, timeout: limit);

      test('ordinary documents and deep ones fit the budget', () {
        final text = StringBuffer('openapi: 3.1.0\npaths:\n');
        for (var i = 0; i < 2000; i++) {
          text.writeln('  /items/$i:\n    get: {summary: s, responses: {}}');
        }
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse('$text', 'api.yaml'), isNotNull);
        expect(bag.all, isEmpty);
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
      const limit = Timeout(Duration(seconds: 30));

      /// A fan-out 9, level 7 alias bomb (written in block style), followed
      /// by [tail].
      String bomb(String tail) {
        final text = StringBuffer(
          'openapi: 3.1.0\nx-bomb:\n  l0: &l0 [x, x, x, x, x, x, x, x, x]\n',
        );
        for (var i = 1; i <= 7; i++) {
          text.writeln('  l$i: &l$i');
          for (var n = 0; n < 9; n++) {
            text.writeln('    - *l${i - 1}');
          }
        }
        text.writeln(tail);
        return '$text';
      }

      test('the bomb itself is bounded by the budget', () {
        final bag = DiagnosticBag();
        expect(SpecLoader(bag).parse(bomb('x-k: 1'), 'api.yaml'), isNull);
        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
      }, timeout: limit);

      test('an alias of a collection as a key is an error, and the rest '
          'of the document is read', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          'openapi: 3.1.0\nx-a: &a [1, 2]\n? *a\n: v\nx-b: 1\n',
          'api.yaml',
        )!;
        expect(doc.root.keys, ['openapi', 'x-a', 'x-b']);
        expect(bag.all.single.code, DiagnosticCode.nonStringKey);
      }, timeout: limit);

      test('aliases everywhere except in keys are accepted', () {
        final bag = DiagnosticBag();
        final doc = SpecLoader(bag).parse(
          '''
openapi: 3.1.0
x-base: &base {a: 1}
x-ref: &ref [1, 2]
x-merge:
  <<: *base
  b: 2
x-value: *ref # the same list
x-own-line:
  *ref
x-seq:
  - *ref
  - - *base
  - k: *base
x-flow: {k: *ref, j: [*ref, *base]}
x-list: [*ref, *ref]
x-text: |
  *x : v
x-md: some *bold* text
  * item
? /pets
: 1
''',
          'api.yaml',
        );
        expect(bag.all, isEmpty);
        expect(doc, isNotNull);
        expect(doc!.root['x-flow'], {
          'k': [1, 2],
          'j': [
            [1, 2],
            {'a': 1},
          ],
        });
      }, timeout: limit);

      test(
        'nesting after a bare block marker line is reported, not a crash',
        () {
          for (final deep in ['- ' * 50000, '[' * 50000]) {
            final bag = DiagnosticBag();
            expect(
              SpecLoader(bag).parse(
                'openapi: 3.1.0\nx:\n  - a\n  -\n    ${deep}x\n',
                'api.yaml',
              ),
              isNull,
            );
            expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
          }
        },
        timeout: limit,
      );
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
