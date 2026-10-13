import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/load/yaml_composer.dart';

void main() {
  group('SpecLoader.parse', () {
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
  });
}
