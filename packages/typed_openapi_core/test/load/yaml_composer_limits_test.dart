import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/compose_fixture.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));
  const fixture = ComposeFixture();
  final compose = fixture.compose;

  group('nesting', () {
    test('every collection the parser opens is a level, keys included', () {
      String nested(int levels) => '${'[' * levels}${']' * levels}';
      expect(compose('a: ${nested(1000)}\n').$2.all, isEmpty);
      expect(
        compose('a: ${nested(1001)}\n').$2.all.single.code,
        DiagnosticCode.nestingTooDeep,
      );
      final (key, bag) = compose('? ${nested(1001)}\n: v\n');
      expect(key, isNull);
      expect(
        bag.all.map((d) => d.code),
        contains(DiagnosticCode.nestingTooDeep),
      );
    }, timeout: limit);

    test('100 000 nested levels are reported, not a stack overflow', () {
      for (final text in [
        '${'[' * 100000}${']' * 100000}',
        '${'- ' * 100000}x',
        '${'{a: ' * 100000}x${'}' * 100000}',
        'x:\n  - a\n  -\n    ${'- ' * 100000}x',
        'x:\n  - a\n  -\n    ${'[' * 100000}',
      ]) {
        final (result, bag) = compose(text);
        expect(result, isNull);
        expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
      }
    }, timeout: limit);
  });

  group('flow collections that hide their closing brackets', () {
    // The scanner copied from package:yaml spent time proportional to the
    // flow depth on every token; each of these took a minute or more. No
    // assertion measures time: the timeout is the test.
    for (final (name, text) in [
      ('quoted closers after a key', 'x: ${'["]",' * 199000}'),
      ('quoted closers after a key, closed', 'x: ${'["]",' * 160000}]'),
      ('quoted closers at the root', '["]",' * 200000),
      ('quoted closers in braces', '{"}":' * 200000),
      ('single-quoted closers', "x: ${"[']'," * 200000}"),
      ('quoted closers on separate lines', 'x: [\n${'"]",[\n' * 150000}'),
      ('closers in comments', 'x: [\n${'[ #]\n' * 150000}'),
      ('a quoted opening bracket first', 'x: ["[", ${'["]",' * 200000}'),
    ]) {
      test('$name are nesting-too-deep, found in near-linear time', () {
        final (result, bag) = compose(text);
        expect(result, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.span, isNotNull);
      }, timeout: limit);
    }

    test(
      'quoted closers without a comma are a syntax error, found at once',
      () {
        // `["]"["]"...`: the parser rejects the second item before the
        // nesting gets deep.
        final (result, bag) = compose('["]"' * 250000);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
      },
      timeout: limit,
    );

    test('the position is the first collection that is too deep', () {
      // `x: ` is 3 characters and each `["]",` starts with its `[`. The
      // root mapping is level 0, so the sequence at index 1000 is level 1001.
      final (_, bag) = compose('x: ${'["]",' * 5000}');
      expect(bag.all.single.span!.start.offset, 3 + 5 * 1000);
    });

    test('many short flow collections are read', () {
      final (result, bag) = compose('x: [${'[1, 2], ' * 60000}0]\n');
      expect(bag.all, isEmpty);
      expect(((result!.root! as Map)['x']! as List).length, 60001);
      expect(compose('{"a": [${'{"k": ["v"]},' * 40000}1]}').$2.all, isEmpty);
      expect(compose('x: ${'["]", ' * 900}${']' * 900}\n').$2.all, isEmpty);
    }, timeout: limit);
  });
}
