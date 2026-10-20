import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';
import 'package:typed_openapi_core/src/load/yaml_composer.dart';

void main() {
  group('SpecLoader.parse', () {
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
  });
}
